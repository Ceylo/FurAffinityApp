//
//  FAKingfisherDownloader+Android.swift
//  FurAffinityUI (Android)
//
//  Kingfisher's transport on Android. Everything above this — the memory and disk
//  caches, coalescing of repeat loads, the processor, `KFImage`'s options — is
//  Kingfisher's; everything below is the OkHttp pipeline this port already had
//  (`FAHttpClient` → `FACoilBridge` → `CoilImageLoader`), which stays because
//  Cloudflare judges a *connection* and pages and images must share one pool.
//
//  `KingfisherManager` reaches a downloader through exactly one method, the
//  `KingfisherParsedOptionsInfo` overload of `downloadImage`, so that is the whole
//  seam. Kingfisher's own `URLSession` is never used here.
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
    static let shared = FAOkHttpDownloader()

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
            guard !Task.isCancelled else { return }
            options.callbackQueue.execute { completionHandler?(result) }
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

        guard let image = options.processor.process(item: .data(data), options: options) else {
            return .failure(.processorError(
                reason: .processingFailed(processor: options.processor, item: .data(data))
            ))
        }
        return .success(ImageLoadingResult(image: image, url: url, originalData: data))
    }
}

enum FAImageError: LocalizedError {
    case loadFailed(URL)

    var errorDescription: String? {
        switch self {
        case let .loadFailed(url): "Image load failed for \(url)"
        }
    }
}
