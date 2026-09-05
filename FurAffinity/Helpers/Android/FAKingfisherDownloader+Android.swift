//
//  FAKingfisherDownloader+Android.swift
//  FurAffinityUI (Android)
//
//  Kingfisher's transport on Android. Everything above this — the memory and disk
//  caches, the processor, `KFImage`'s options — is Kingfisher's; everything below is
//  the OkHttp pipeline this port already had
//  (`FAHttpClient` → `FAImageFetchBridge` → `ImageFetchBridge`), which stays because
//  Cloudflare judges a *connection* and pages and images must share one pool.
//
//  `KingfisherManager` reaches a downloader through exactly one method, the
//  `KingfisherParsedOptionsInfo` overload of `downloadImage`, so that is the whole
//  seam. Kingfisher's own `URLSession` is never used here.
//
//  Coalescing is the one thing that does not come with it: Kingfisher dedupes inside
//  `SessionDataTask`/`SessionDelegate`, which this never reaches. Hence
//  `FAImageStore.bytes(for:)` for the download and `DecodeCoalescer` for the decode.
//
//  Unguarded on purpose — an Android substitution file must be, see
//  Android/docs/shared-sources.md § Rules for shared sources. The JNI it reaches is
//  `canImport(Android)`-guarded further down and no-ops on Darwin.
//

import Foundation
import Kingfisher

/// `ImageDownloader` over the app's OkHttp client.
///
/// The Cloudflare machinery is unchanged and lives in `FAImageStore`: the two-FIFO
/// permit gate, parking *inside* the permit on an unresolved challenge, the
/// epoch-guarded pool repair and the single post-repair retry. This type only turns
/// the on-disk path that comes back into the `ImageLoadingResult` Kingfisher expects.
final class FAOkHttpDownloader: ImageDownloader, @unchecked Sendable {
    /// `delegate` is `weak`; `DownloadDelegate.shared` is what keeps it alive.
    @MainActor static let shared: FAOkHttpDownloader = {
        let downloader = FAOkHttpDownloader()
        downloader.delegate = DownloadDelegate.shared
        return downloader
    }()

    private init() {
        super.init(name: "FurAffinity OkHttp Downloader")
    }

    override func downloadImage(
        with url: URL,
        options: KingfisherParsedOptionsInfo,
        completionHandler: (@Sendable (Result<ImageLoadingResult, KingfisherError>) -> Void)? = nil
    ) -> DownloadTask {
        // `ImagePrefetcher` is the only caller that lowers the priority, which is
        // exactly the visible-vs-prefetch split the gate's two FIFOs want.
        let priority: FAImagePriority =
            options.downloadPriority < FADownloadPriority.normal ? .low : .high

        let work = Task(priority: priority.taskPriority) { [weak self] in
            guard let self else { return }
            let result = await self.load(url, priority: priority, options: options)
            // A completion on *every* path, cancellation included:
            // `KingfisherManager.retrieveImage`'s async form resumes its continuation
            // only from here, so returning silently strands the caller — and
            // `InFlightCoalescer`'s `inFlight[key]` — forever.
            // `.asyncTaskContextCancelled` is what `KingfisherManager` itself reports
            // for this, and the only cancellation reason constructible from outside.
            let delivered: Result<ImageLoadingResult, KingfisherError> = Task.isCancelled
                ? .failure(.requestError(reason: .asyncTaskContextCancelled))
                : result
            options.callbackQueue.execute { completionHandler?(delivered) }
        }
        return DownloadTask(cancelling: work)
    }

    private func load(
        _ url: URL,
        priority: FAImagePriority,
        options: KingfisherParsedOptionsInfo
    ) async -> Result<ImageLoadingResult, KingfisherError> {
        // The delegate is what makes `SubmissionFeedItemView.controlCacheBehavior`
        // one implementation on both platforms; on iOS the URLSession downloader
        // calls the same hook.
        delegate?.imageDownloader(self, willDownloadImageForURL: url, with: nil)
        defer {
            delegate?.imageDownloader(
                self, didFinishDownloadingImageForURL: url, with: nil, error: nil
            )
        }

        guard let data = await FAImageStore.shared.bytes(for: url, priority: priority) else {
            return .failure(.responseError(reason: .URLSessionError(error: FAImageError.loadFailed(url))))
        }

        // Through the gate, not straight here: the processor decodes, and a decode is
        // another blocking JNI call on a thread Swift concurrency owns. And through
        // the coalescer, since `bytes(for:)` only coalesces the *download*: N views of
        // one avatar would run one fetch and N decodes, one permit each. The processor
        // is in the key because what is shared is the *processed* image.
        let key = "\(url.absoluteString)|\(options.processor.identifier)"
        let image = await decodes.run(key) {
            await FAImageStore.shared.decoding(priority) {
                options.processor.process(item: .data(data), options: options)
            }
        }
        guard let image else {
            return .failure(.processorError(
                reason: .processingFailed(processor: options.processor, item: .data(data))
            ))
        }
        return .success(ImageLoadingResult(image: image, url: url, originalData: data))
    }
}

private let decodes = InFlightCoalescer<String, KFCrossPlatformImage?>()

enum FAImageError: LocalizedError {
    case loadFailed(URL)

    var errorDescription: String? {
        switch self {
        case let .loadFailed(url): "Image load failed for \(url)"
        }
    }
}
