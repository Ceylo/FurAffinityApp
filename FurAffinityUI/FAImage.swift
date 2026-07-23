//
//  FAImage.swift
//  FurAffinityUI (Android)
//
//  The Android counterpart of the iOS `Kingfisher+FA.swift`. iOS renders FA images
//  with Kingfisher (`FAImage`/`FAAnimatedImage` return `KFImage`/`KFAnimatedImage`);
//  Android can't compile Kingfisher's ImageIO pipeline, so here `FAImage(_:)` /
//  `FAAnimatedImage(_:)` return `FAImageView` — a small SwiftUI view that loads encoded
//  bytes through `CoilImageLoader` (Coil 3 + FA's Cloudflare headers) and renders
//  `Image(uiImage:)`.
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

/// A KFImage-shaped SwiftUI view backed by Coil. The KF-style configuration methods
/// return `Self` so callers can chain `.placeholder { }.onFailure { }.fade(...)` exactly
/// as on iOS; the trailing standard modifiers (`.aspectRatio`, `.onAppear`, …) then
/// apply to the resulting `View`.
struct FAImageView: View {
    let url: URL?
    fileprivate var placeholderView: AnyView?
    fileprivate var onFailureHandler: ((any Error) -> Void)?
    fileprivate var fadeDuration: Double = 0

    // @State on a bridged view must be internal, not private (Skip inventory #5).
    @State var image: UIImage?

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
            } else if let placeholderView {
                placeholderView
            } else {
                Color.clear
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        image = nil
        guard let url else { return }
        if let data = await CoilImageLoader.load(url), let decoded = UIImage(data: data) {
            if fadeDuration > 0 {
                withAnimation(.easeInOut(duration: fadeDuration)) { image = decoded }
            } else {
                image = decoded
            }
        } else {
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

/// Warm Coil's disk cache for `urls` (fire-and-forget).
func prefetch(_ urls: [URL]) {
    for url in urls {
        Task.detached { _ = await CoilImageLoader.load(url) }
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
    // Warms the base thumbnail URLs (what the feed view requests). Size-optimized
    // variants via `dynamicThumbnail.bestThumbnailUrl(for: CGSize)` are deferred: CGSize
    // is ambiguous and CoreGraphics isn't importable in the native module. `_ =
    // availableWidth` keeps the shared call-site signature until that refinement lands.
    _ = availableWidth
    prefetch(previews.map(\.thumbnailUrl))
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
