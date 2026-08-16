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
    // Read out of the carrier once — `body` runs on every recomposition of every row,
    // and each pass rebuilds every fragment's markup into a fresh String.
    var fragments: [FAHTMLFragment.Carried]
    @Environment(\.openURL) var openURL

    init(text: AttributedString, initialHeight: CGFloat = 0) {
        self.fragments = text.faHTMLFragments
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(fragments, id: \.fragment.index) { carried in
                if carried.fragment.index > 0 {
                    Divider()
                }
                fragment(carried)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Matches the iOS view's `textContainerInset = 3` on all edges.
        .padding(3)
    }

    private func fragment(_ carried: FAHTMLFragment.Carried) -> Text {
        #if canImport(Android)
        Text(
            html: carried.html,
            inlineViews: carried.fragment.images.map { image in
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
                // this is the app's chance to keep a navigable FA URL in-app. The scheme
                // rewrite is what tells `AndroidRootView`'s handler the two apart.
                openURL(url.convertedForInAppNavigation)
            }
        )
        #else
        // The module's Darwin bridge compiles against real SwiftUI, which has no
        // HTML-parsing `Text`; this branch only has to typecheck. The file itself stays
        // unguarded so shared callers still find it.
        Text(verbatim: carried.html)
        #endif
    }
}

private extension FAInlineImage {
    /// Compose reserves an inline placeholder's space before composing anything into
    /// it, so every image needs a size up front — from the markup where it states one,
    /// and otherwise from what FA's stylesheet would have given it.
    var displayWidth: Double { width ?? fallbackExtent }
    var displayHeight: Double { height ?? fallbackExtent }

    /// `.iconusername` avatars are capped at 50×50; everything else left unsized is a
    /// smilie, which sits on one line of text.
    private var fallbackExtent: Double { isAvatar ? 50 : 19 }
}
