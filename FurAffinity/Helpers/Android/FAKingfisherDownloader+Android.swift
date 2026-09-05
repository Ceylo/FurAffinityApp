//
//  FAKingfisherDownloader+Android.swift
//  FurAffinityUI (Android)
//
//  Kingfisher's transport on Android. Everything above this — the memory and disk
//  caches, the processor, `KFImage`'s options — is Kingfisher's; everything below is
//  the OkHttp pipeline this port already had
//  (`FAHttpClient` → `FACoilBridge` → `CoilImageLoader`), which stays because
//  Cloudflare judges a *connection* and pages and images must share one pool.
//
//  `KingfisherManager` reaches a downloader through exactly one method, the
//  `KingfisherParsedOptionsInfo` overload of `downloadImage`, so that is the whole
//  seam. Kingfisher's own `URLSession` is never used here.
//
//  Coalescing is the one thing that does *not* come for free with it: Kingfisher
//  dedupes concurrent loads inside `SessionDataTask`/`SessionDelegate`, which a
//  downloader replacing the transport never reaches. So the download is coalesced by
//  `FAImageStore.bytes(for:)` and the decode by `DecodeCoalescer` below.
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
    /// `delegate` is `weak`; `DownloadDelegate.shared`, a `static let`, is what keeps
    /// it alive. `@MainActor` to match it and `faImageDownloader`, the only reader.
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
            // only from this handler — its `onCancel` merely calls `task.cancel()` —
            // so returning silently here strands the caller forever, and strands
            // `InFlightCoalescer`'s `inFlight[key]` with it. `.asyncTaskContextCancelled`
            // is the reason `KingfisherManager` itself uses for a cancelled async
            // context, and the only cancellation reason constructible from outside the
            // module. iOS already reports one (URLSession delivers `.taskCancelled`).
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
        // the coalescer, because `bytes(for:)` only coalesces the *download*: N views
        // of one avatar would otherwise run one fetch and N decodes, each taking one
        // of the gate's six permits.
        let image = await decodes.image(for: url, options: options) {
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

/// Coalesces concurrent decodes of the same processed image.
///
/// Kingfisher dedupes concurrent `retrieveImage` calls inside
/// `SessionDataTask`/`SessionDelegate`, which a downloader replacing the transport
/// never reaches, so this is the counterpart of `FAImageStore.bytes(for:)` for the
/// decode. The processor is part of the key: what is shared is the *processed* image.
private actor DecodeCoalescer {
    private var inFlight = [String: Task<KFCrossPlatformImage?, Never>]()

    func image(
        for url: URL,
        options: KingfisherParsedOptionsInfo,
        decode: @escaping @Sendable () async -> KFCrossPlatformImage?
    ) async -> KFCrossPlatformImage? {
        let key = "\(url.absoluteString)|\(options.processor.identifier)"
        if let existing = inFlight[key] {
            return await existing.value
        }
        // Unstructured, like `bytes(for:)`: one caller cancelling must not cancel the
        // decode the others are waiting on. The starter clears the entry.
        let task = Task { await decode() }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        return image
    }
}

private let decodes = DecodeCoalescer()

enum FAImageError: LocalizedError {
    case loadFailed(URL)

    var errorDescription: String? {
        switch self {
        case let .loadFailed(url): "Image load failed for \(url)"
        }
    }
}
