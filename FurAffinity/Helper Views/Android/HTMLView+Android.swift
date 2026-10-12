//
//  HTMLView.swift
//  FurAffinityUI (Android)
//
//  Android counterpart of the iOS `HTMLView`. The iOS one is a `UIViewRepresentable` over
//  a manually sized `UITextView` with animated-GIF overlays; none of that exists here, and
//  none of it needs to — Compose parses HTML itself, so `FAHTMLNormalizer` hands over the
//  markup and `Text(html:)` renders it, paragraph alignment and all.
//
//  Two things the parser drops are put back here. `<hr>` renders as nothing at all, so the
//  normaliser cuts the markup at its rules and a `Divider()` goes between the pieces. And
//  `<img>` leaves only a U+FFFC behind, which is exactly where `inlineViews` splice in.
//
//  `initialHeight` is accepted and ignored — it only ever seeded the iOS manual sizing.
//

import SwiftUI
import FAKit

struct HTMLView: View {
    // Not private: skipstone can't bridge a private @State/@Environment.
    // Read out of the carrier here rather than in `body`: `init` still runs on every
    // evaluation of the parent's body, but the walk is O(runs) with nothing built.
    var fragments: [FAHTMLFragment]
    @Environment(\.openURL) var openURL
    @Environment(\.navigationStream) var navigationStream
    /// What an image may span, as FA caps `bbcode_img` at the description's width.
    @State var availableWidth: CGFloat = 0
    /// Each image's own size, once `FAImage` has loaded it here. Until then it gets
    /// the size an earlier view learned, else a fallback: the text never waits on it.
    @State var naturalSizes: [URL: Foundation.CGSize] = [:]

    init(text: AttributedString, initialHeight: CGFloat = 0) {
        self.fragments = text.faHTMLFragments
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(fragments, id: \.index) { fragment in
                if fragment.index > 0 {
                    Divider()
                }
                render(fragment)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
        // Matches what the iOS view insets text by: `textContainerInset = 3` on all
        // edges, plus the 5 pt `lineFragmentPadding` a `UITextView` keeps on its
        // leading/trailing edges by default (never zeroed in `makeUIView`).
        .padding(.vertical, 3)
        .padding(.horizontal, 8)
    }

    private func render(_ fragment: FAHTMLFragment) -> Text {
        #if canImport(Android)
        Text(
            html: fragment.html,
            inlineViews: fragment.images.map { image in
                let size = image.displaySize(
                    natural: naturalSizes[image.url] ?? InlineImageSizes.known[image.url],
                    maxWidth: Double(availableWidth)
                )
                return TextInlineView(
                    FAImage(image.url)
                        .onSuccess { result in
                            let natural = Foundation.CGSize(result.image.size)
                            // Recomposes the whole view: only when the layout changes.
                            guard image.width == nil || image.height == nil,
                                  (naturalSizes[image.url] ?? InlineImageSizes.known[image.url]) != natural
                            else { return }
                            InlineImageSizes.known[image.url] = natural
                            naturalSizes[image.url] = natural
                        }
                        .resizable()
                        .frame(width: Double(size.width), height: Double(size.height)),
                    width: Double(size.width),
                    height: Double(size.height)
                )
            },
            onLinkTap: { url in
                // Compose hands the tap here instead of opening the browser itself, so
                // this is the app's chance to keep a navigable FA URL in-app. Only links
                // *inside rich text* land here, so matching plainly on `FATarget` is
                // safe: "Open in Web Browser" goes through `openURL` and never here.
                //
                // Compose's LinkInteractionListener fires on the UI thread, so this is
                // already the main actor — assume it rather than hopping through a Task,
                // which would defer the push by a frame.
                MainActor.assumeIsolated {
                    if let target = FATarget(with: url) {
                        navigationStream.send(target)
                    } else {
                        openURL(url)
                    }
                }
            }
        )
        #else
        // The module's Darwin bridge compiles against real SwiftUI, which has no
        // HTML-parsing `Text`; this branch only has to typecheck. The file itself stays
        // unguarded so shared callers still find it.
        Text(verbatim: fragment.html)
        #endif
    }
}

/// Every inline image's own size learnt so far, so a view built again (a recycled row,
/// a revisited page) lays out what is already cached at its real size from the start.
@MainActor
private enum InlineImageSizes {
    static var known: [URL: Foundation.CGSize] = [:]
}

private extension FAInlineImage {
    /// Compose reserves an inline placeholder's space before composing anything into
    /// it, so every image needs a size up front: the one the markup states, completed
    /// or replaced by the image's own once loaded, then capped as FA's stylesheet caps it.
    func displaySize(natural: Foundation.CGSize?, maxWidth: Double) -> Foundation.CGSize {
        var size = intrinsicSize(natural: natural)
        // `.iconusername img` is capped at 50×50.
        if isAvatar {
            size = size.fitting(in: Foundation.CGSize(width: 50, height: 50))
        }
        // `bbcode_img` is capped at the description's width; nothing is ever wider.
        if maxWidth > 0 {
            size = size.fitting(in: Foundation.CGSize(width: maxWidth, height: .infinity))
        }
        return size
    }

    private func intrinsicSize(natural: Foundation.CGSize?) -> Foundation.CGSize {
        let natural = natural.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil }
        switch (width, height, natural) {
        case let (width?, height?, _):
            return Foundation.CGSize(width: width, height: height)
        case let (width?, nil, natural?):
            return Foundation.CGSize(width: width, height: width * natural.height / natural.width)
        case let (nil, height?, natural?):
            return Foundation.CGSize(width: height * natural.width / natural.height, height: height)
        case let (nil, nil, natural?):
            return natural
        default:
            // One side alone would squash the image for good, which is worse than the
            // square a fallback gives it.
            return Foundation.CGSize(width: fallbackExtent, height: fallbackExtent)
        }
    }

    /// What an image not loaded yet gets: `.iconusername` avatars are capped at 50×50,
    /// and everything else is most likely a smilie, which sits on one line of text.
    private var fallbackExtent: Double { isAvatar ? 50 : 19 }
}
