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
    // Not private: skipstone can't bridge a private state property.
    // Read out of the carrier here rather than in `body`: `init` still runs on every
    // evaluation of the parent's body, but the walk is O(runs) with nothing built.
    var fragments: [FAHTMLFragment]
    @Environment(\.openURL) var openURL
    @Environment(\.navigationStream) var navigationStream

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
                TextInlineView(
                    FAImage(image.url)
                        .resizable()
                        .frame(width: image.displayWidth, height: image.displayHeight),
                    width: image.displayWidth,
                    height: image.displayHeight
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
    /// it, so every image needs a size up front — from the markup where it states one,
    /// and otherwise from what FA's stylesheet would have given it.
    var displayWidth: Double { statedSize?.width ?? fallbackExtent }
    var displayHeight: Double { statedSize?.height ?? fallbackExtent }

    /// Both or neither: a 300×19 slot squashes the image for good, which is worse than
    /// the 19×19 one a fallback gives it.
    private var statedSize: (width: Double, height: Double)? {
        guard let width, let height else { return nil }
        return (width, height)
    }

    /// `.iconusername` avatars are capped at 50×50; everything else left unsized is a
    /// smilie, which sits on one line of text.
    private var fallbackExtent: Double { isAvatar ? 50 : 19 }
}
