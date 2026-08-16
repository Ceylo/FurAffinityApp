//
//  FAImage.swift
//  FurAffinityUI (Android)
//
//  The Android counterpart of the iOS `Kingfisher+FA.swift`. iOS renders FA images
//  with Kingfisher (`FAImage`/`FAAnimatedImage` return `KFImage`/`KFAnimatedImage`);
//  Android can't compile Kingfisher's ImageIO pipeline, so here `FAImage(_:)` /
//  `FAAnimatedImage(_:)` return `FAImageView` — a small SwiftUI view that renders
//  `Image(uiImage:)` from `FAImageStore` (memory cache + coalescing + bounded, off-main
//  fetch and decode over `CoilImageLoader`).
//
//  `FAImageView` mirrors the slice of Kingfisher's `KFImage` API the shared feed uses
//  (`.placeholder`, `.onFailure`, `.fade`, `.resizable`) so a symlinked
//  `SubmissionFeedItemView` compiles unchanged on both platforms. Animated GIFs are a
//  deferred follow-up: `FAAnimatedImage` shows the first frame for now (static).
//

import Foundation
import SwiftUI
import FAKit
import FAPages

/// A KFImage-shaped SwiftUI view backed by `FAImageStore`. The KF-style configuration methods
/// return `Self` so callers can chain `.placeholder { }.onFailure { }.fade(...)` exactly
/// as on iOS; the trailing standard modifiers (`.aspectRatio`, `.onAppear`, …) then
/// apply to the resulting `View`.
struct FAImageView: View {
    let url: URL?
    fileprivate var placeholderView: AnyView?
    fileprivate var failureView: AnyView?
    fileprivate var onFailureHandler: ((any Error) -> Void)?
    fileprivate var fadeDuration: Double = 0

    // @State on a bridged view must be internal, not private (Skip inventory #5).
    @State var image: UIImage?
    @State var failed = false

    init(_ url: URL?) {
        self.url = url
    }

    func placeholder<P: View>(@ViewBuilder _ content: () -> P) -> Self {
        var copy = self
        copy.placeholderView = AnyView(content())
        return copy
    }

    func onFailure(_ handler: @escaping (any Error) -> Void) -> Self {
        var copy = self
        copy.onFailureHandler = handler
        return copy
    }

    /// Shown instead of the placeholder once the load has failed.
    func onFailureView<P: View>(@ViewBuilder _ content: () -> P) -> Self {
        var copy = self
        copy.failureView = AnyView(content())
        return copy
    }

    func fade(duration: Double) -> Self {
        var copy = self
        copy.fadeDuration = duration
        return copy
    }

    /// KFImage-compatibility no-op: the rendered `Image` is already `.resizable()`.
    func resizable() -> Self { self }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
            } else if failed, let failureView {
                failureView
            } else if let placeholderView {
                placeholderView
            } else {
                Color.clear
            }
        }
        // Not `withAnimation`: it marks the whole Compose frame on SkipUI.
        .animation(fadeDuration > 0 ? .easeInOut(duration: fadeDuration) : nil,
                   value: image != nil)
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let url else {
            image = nil
            failed = true
            return
        }
        // Seed from the memory cache so a row scrolled back into view renders on its
        // first frame. Only clear a stale image when the URL actually changed —
        // resetting unconditionally is what makes every re-appearance flash its
        // placeholder.
        if let cached = FAImageStore.shared.cachedImage(for: url) {
            logger.debug("render memory url=\(url.absoluteString)")
            image = cached
            failed = false
            return
        }
        image = nil
        failed = false

        let start = Date()
        let loaded = await FAImageStore.shared.image(for: url)
        let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
        logger.debug("render \(elapsedMs)ms url=\(url.absoluteString)")
        if let loaded {
            image = loaded
        } else {
            failed = true
            onFailureHandler?(FAImageError.loadFailed(url))
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

func FAImage(_ url: URL?) -> FAImageView {
    FAImageView(url)
}

/// Static first — animated GIF avatars are a deferred follow-up (needs `coil-gif`).
func FAAnimatedImage(_ url: URL?) -> FAImageView {
    FAImageView(url)
}

// MARK: - Prefetching (mirrors Kingfisher+FA.swift so shared list views compile)

/// How many leading URLs are warmed at high priority, matching
/// `Kingfisher+FA.swift`'s split: the first screenful should not queue behind the
/// rest of the page.
private let highPriorityPrefetchCount = 3

/// Warm the disk cache for `urls` (fire-and-forget).
///
/// Deduplicated first: one author can appear a dozen times in a feed page, and the
/// avatar list would otherwise ask for the same URL a dozen times.  `FAImageStore`
/// coalesces the rest — including against a visible row's own load — and bounds the
/// concurrency, so this no longer spawns one blocking task per URL.
func prefetch(_ urls: [URL]) {
    var seen = Set<URL>()
    let unique = urls.filter { seen.insert($0).inserted }
    logger.debug("prefetch \(unique.count) urls (\(urls.count) before dedupe)")
    for (index, url) in unique.enumerated() {
        let priority: FAImagePriority = index < highPriorityPrefetchCount ? .high : .low
        Task(priority: priority.taskPriority) {
            await FAImageStore.shared.warm(url, priority: priority)
        }
    }
}

func prefetchAvatars(for comments: some Collection<FAComment>) {
    var visible = [FAVisibleComment]()
    comments.recursiveForEach { comment in
        if case .visible(let visibleComment) = comment {
            visible.append(visibleComment)
        }
    }
    prefetch(visible.compactMap { FAURLs.avatarUrl(for: $0.author) })
}

func prefetchAvatars(for previews: some Collection<FASubmissionPreview>) {
    prefetch(previews.compactMap { FAURLs.avatarUrl(for: $0.author) })
}

func prefetchThumbnails(for previews: some Collection<FASubmissionPreview>, availableWidth: Double) {
    logger.debug("prefetchThumbnails count=\(previews.count) availableWidth=\(availableWidth)")
    // thumbnailWidthOnHeightRatio = width / height, so height = width / ratio.
    // Foundation.CGSize (explicitly qualified — SkipSwiftUI's CGSize is also in scope)
    // built straight from Doubles here, so no bridging cast is needed.
    prefetch(previews.map { preview in
        let size = Foundation.CGSize(
            width: availableWidth,
            height: availableWidth / Double(preview.thumbnailWidthOnHeightRatio)
        )
        return preview.dynamicThumbnail.bestThumbnailUrl(for: size)
    })
}

extension View {
    /// Prefetches thumbnails and avatars for `previews` whenever they change (and once
    /// on appear), so a feed/results list has its images warming before the user
    /// scrolls. Mirrors the iOS modifier so shared list views compile unchanged.
    /// `Double` (== CGFloat here) sidesteps the ambiguous-CGFloat lookup in this module.
    func prefetchingPreviews<C: Collection<FASubmissionPreview> & Equatable>(
        _ previews: C?,
        availableWidth: Double
    ) -> some View {
        onChange(of: previews, initial: true) { _, newValue in
            guard let newValue else { return }
            prefetchThumbnails(for: newValue, availableWidth: availableWidth)
            prefetchAvatars(for: newValue)
        }
    }
}
