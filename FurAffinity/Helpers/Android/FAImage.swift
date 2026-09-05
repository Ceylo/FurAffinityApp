//
//  FAImage.swift
//  FurAffinityUI (Android)
//
//  The Android counterpart of `FAImage(_:)`/`FAAnimatedImage(_:)`. Loading, caching
//  and the Cloudflare-aware transport are Kingfisher's on this platform too (see
//  `Kingfisher+FA.swift` and `FAKingfisherDownloader+Android.swift`); what is still
//  missing is Kingfisher's *SwiftUI* layer, which needs `ObservableObject` and
//  Combine. Until that is ported, `FAImageView` renders `Image(uiImage:)` from
//  `KingfisherManager` and mirrors the slice of `KFImage`'s API the shared views use
//  (`.placeholder`, `.onFailure`, `.fade`, `.resizable`), so `AvatarView` and
//  `SubmissionMainImage` compile from one source on both platforms.
//
//  `FAAnimatedImage` is the same static view: Android's decode seam has no animated
//  path, so a GIF shows its first frame.
//

import Foundation
import SwiftUI
import FAKit
import Kingfisher

/// A KFImage-shaped SwiftUI view backed by `KingfisherManager`. The KF-style
/// configuration methods return `Self` so callers can chain
/// `.placeholder { }.onFailure { }.fade(...)` exactly as on iOS; the trailing standard
/// modifiers (`.aspectRatio`, `.onAppear`, …) then apply to the resulting `View`.
struct FAImageView: View {
    let url: URL?
    fileprivate var placeholderView: AnyView?
    fileprivate var failureView: AnyView?
    fileprivate var onFailureHandler: ((any Error) -> Void)?
    fileprivate var fadeDuration: Double = 0

    // Not private: skipstone can't bridge a private @State/@Environment.
    @State var image: UIImage?
    @State var failed = false

    init(_ url: URL?) {
        self.url = url
        // Seeded synchronously: `.task` cannot run before the first composition, so a
        // re-composed row would otherwise paint its placeholder for a frame even on a
        // guaranteed memory-cache hit.
        _image = State(initialValue: url.flatMap { Self.cachedImage(for: $0) })
    }

    /// Kingfisher's memory cache, read without suspending.
    private static func cachedImage(for url: URL) -> UIImage? {
        ImageCache.default.retrieveImageInMemoryCache(forKey: url.cacheKey)
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
        if let cached = Self.cachedImage(for: url) {
            image = cached
            failed = false
            return
        }
        image = nil
        failed = false

        do {
            image = try await KingfisherManager.shared.retrieveFAImage(with: url)
        } catch {
            failed = true
            onFailureHandler?(error)
        }
    }
}

func FAImage(_ url: URL?) -> FAImageView {
    FAImageView(url)
}

/// Static first — an animated GIF would need an animated decode path, which the
/// Bitmap-backed `UIImage` behind Kingfisher's Android decode seam does not have.
func FAAnimatedImage(_ url: URL?) -> FAImageView {
    FAImageView(url)
}
