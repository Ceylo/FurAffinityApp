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
                let size = image.displaySize(maxWidth: Double(availableWidth))
                return TextInlineView(
                    FAImage(image.url)
                        .resizable()
                        .frame(width: size.width, height: size.height),
                    width: size.width,
                    height: size.height
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

private extension FAInlineImage {
    /// Compose reserves an inline placeholder's space before composing anything into
    /// it, so every image needs a size up front: the one the markup states, completed
    /// or replaced by the image's own, then capped as FA's stylesheet caps it.
    func displaySize(maxWidth: Double) -> (width: Double, height: Double) {
        var size = intrinsicSize
        // `.iconusername img` is capped at 50×50.
        if isAvatar {
            size = Self.fitting(size, maxWidth: 50, maxHeight: 50)
        }
        // `bbcode_img` is capped at the description's width; nothing is ever wider.
        if maxWidth > 0 {
            size = Self.fitting(size, maxWidth: maxWidth, maxHeight: .infinity)
        }
        return size
    }

    private var intrinsicSize: (width: Double, height: Double) {
        let natural: (width: Double, height: Double)? = {
            guard let naturalWidth, let naturalHeight, naturalHeight > 0 else { return nil }
            return (naturalWidth, naturalHeight)
        }()
        switch (width, height, natural) {
        case let (width?, height?, _):
            return (width, height)
        case let (width?, nil, natural?):
            return (width, width * natural.height / natural.width)
        case let (nil, height?, natural?):
            return (height * natural.width / natural.height, height)
        case let (nil, nil, natural?):
            return natural
        default:
            // One side alone would squash the image for good, which is worse than the
            // square a fallback gives it.
            return (fallbackExtent, fallbackExtent)
        }
    }

    /// Scales down, never up, keeping the aspect ratio.
    private static func fitting(
        _ size: (width: Double, height: Double), maxWidth: Double, maxHeight: Double
    ) -> (width: Double, height: Double) {
        let scale = min(1, maxWidth / size.width, maxHeight / size.height)
        return (size.width * scale, size.height * scale)
    }

    /// What an image never fetched gets: `.iconusername` avatars are capped at 50×50,
    /// and everything else is most likely a smilie, which sits on one line of text.
    private var fallbackExtent: Double { isAvatar ? 50 : 19 }
}
