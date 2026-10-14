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
//  `loads`, which covers the download and the decode as one unit.
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
            let (result, held) = await self.load(url, priority: priority, options: options)
            // A completion on *every* path, cancellation included:
            // `KingfisherManager.retrieveImage`'s async form resumes its continuation
            // only from here, so returning silently strands the caller — and
            // `InFlightCoalescer`'s `inFlight[key]` — forever.
            // `.asyncTaskContextCancelled` is what `KingfisherManager` itself reports
            // for this, and the only cancellation reason constructible from outside.
            let delivered: Result<ImageLoadingResult, KingfisherError> = Task.isCancelled
                ? .failure(.requestError(reason: .asyncTaskContextCancelled))
                : result
            options.callbackQueue.execute {
                completionHandler?(delivered)
                // Kingfisher's memory store ran synchronously inside that call.
                if let held { recentLoads.delivered(held) }
            }
        }
        return DownloadTask(cancelling: work)
    }

    private func load(
        _ url: URL,
        priority: FAImagePriority,
        options: KingfisherParsedOptionsInfo
    ) async -> (Result<ImageLoadingResult, KingfisherError>, RecentLoads.Hold?) {
        // The delegate is what makes `SubmissionFeedItemView.controlCacheBehavior`
        // one implementation on both platforms; on iOS the URLSession downloader
        // calls the same hook.
        delegate?.imageDownloader(self, willDownloadImageForURL: url, with: nil)
        defer {
            delegate?.imageDownloader(
                self, didFinishDownloadingImageForURL: url, with: nil, error: nil
            )
        }

        // The OkHttp fetch blocks until the file is written, so its copy loop pushes
        // progress instead. Subscribed here, before the fetch, so no push is missed; a
        // load still queued behind `FAImageStore`'s gate just waits on an empty stream.
        let progressUpdates = ImageFetchBridge.progressUpdates(for: url)
        let progressForwarder = Task {
            for await update in progressUpdates {
                options.reportDownloadProgress(
                    receivedSize: update.received, totalSize: update.total
                )
            }
        }
        defer { progressForwarder.cancel() }

        // Download and decode coalesce as one unit: `bytes(for:)` alone only covers the
        // download, and its entry clears while the decode still waits for a permit
        // behind every queued prefetch — seconds in which a URL is neither in flight
        // nor cached, so a second prefetch pass redialled it (up to ~70 GETs per cold
        // launch). The processor is in the key because what is shared is the
        // *processed* image.
        let key = "\(url.absoluteString)|\(options.processor.identifier)"
        let loaded = await loads.run(key, priority: priority.taskPriority) {
            if let recent = recentLoads.value(for: key) {
                if let image = recent.image
                    ?? ImageCache.default.retrieveImageInMemoryCache(forKey: url.cacheKey, options: options) {
                    return .image(image, recent.data, nil)
                }
                let image = await FAImageStore.shared.decoding(priority) {
                    options.processor.process(item: .data(recent.data), options: options)
                }
                return image.map { .image($0, recent.data, nil) } ?? .undecodable(recent.data)
            }
            guard let data = await FAImageStore.shared.bytes(for: url, priority: priority) else {
                return Loaded.noBytes
            }
            // Through the gate, not straight here: the processor decodes, and a
            // decode is another blocking JNI call on a thread Swift concurrency owns.
            let image = await FAImageStore.shared.decoding(priority) {
                options.processor.process(item: .data(data), options: options)
            }
            guard let image else { return .undecodable(data) }
            // Recorded before the coalescer entry clears, so there is no gap between the two.
            return recentLoads.hold(image, data, for: key)
        }

        switch loaded {
        case .noBytes:
            return (.failure(.responseError(reason: .URLSessionError(error: FAImageError.loadFailed(url)))), nil)
        case let .undecodable(data):
            return (.failure(.processorError(
                reason: .processingFailed(processor: options.processor, item: .data(data))
            )), nil)
        case let .image(image, data, hold):
            return (.success(ImageLoadingResult(image: image, url: url, originalData: data)), hold)
        }
    }
}

private enum Loaded: Sendable {
    case noBytes
    case undecodable(Data)
    /// The hold is nil when the image was served from `recentLoads` rather than loaded.
    case image(KFCrossPlatformImage, Data, RecentLoads.Hold?)
}

private let loads = InFlightCoalescer<String, Loaded>()

/// Images loaded moments ago, so a load arriving just after the coalescer entry
/// clears is served without a GET. Two such arrivals, both measured on a cold launch:
/// before Kingfisher's memory-cache store, which runs in the completion on
/// `callbackQueue` (main for a prefetch, busy as the second pass starts); and after
/// it, from a caller whose own cache lookup — queued on Kingfisher's disk queue
/// behind the burst's writes — missed before the store.
private let recentLoads = RecentLoads()

private final class RecentLoads: @unchecked Sendable {
    struct Hold: Sendable {
        fileprivate let key: String
        fileprivate let id: UInt64
    }

    struct Entry {
        let data: Data
        /// Until the first delivery; Kingfisher's memory cache owns it after that.
        var image: KFCrossPlatformImage?
        fileprivate let id: UInt64
    }

    /// Encoded bytes only, once delivered: a few seconds of a cold burst's thumbnails.
    private static let byteLimit = 8 * 1024 * 1024

    private let lock = NSLock()
    private var entries = [String: Entry]()
    private var order = [String]()
    private var byteCount = 0
    private var lastID: UInt64 = 0

    func hold(_ image: KFCrossPlatformImage, _ data: Data, for key: String) -> Loaded {
        lock.withLock {
            lastID += 1
            if let old = entries.removeValue(forKey: key) {
                byteCount -= old.data.count
                order.removeAll { $0 == key }
            }
            entries[key] = Entry(data: data, image: image, id: lastID)
            order.append(key)
            byteCount += data.count
            evictDelivered()
            return .image(image, data, Hold(key: key, id: lastID))
        }
    }

    func value(for key: String) -> Entry? {
        lock.withLock { entries[key] }
    }

    /// Drops the image, keeping the bytes. Only the hold's own entry: a later load of
    /// the same key must keep its image.
    func delivered(_ hold: Hold) {
        lock.withLock {
            guard entries[hold.key]?.id == hold.id else { return }
            entries[hold.key]?.image = nil
            evictDelivered()
        }
    }

    /// Oldest first, and never an undelivered entry: that one is what closes the gap.
    private func evictDelivered() {
        var index = 0
        while byteCount > Self.byteLimit, index < order.count {
            let key = order[index]
            if let entry = entries[key], entry.image == nil {
                byteCount -= entry.data.count
                entries[key] = nil
                order.remove(at: index)
            } else {
                index += 1
            }
        }
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
