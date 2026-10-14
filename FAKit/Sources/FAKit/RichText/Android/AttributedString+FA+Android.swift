//
//  AttributedString+FA+Android.swift
//  FAKit
//
//  Keeps the `+Android` suffix its iOS counterpart drops: SwiftPM derives an
//  object file per source *basename*, so two files named AttributedString+FA.swift
//  in one target fail the build with "multiple producers" — the `iOS/` and
//  `Android/` directories cannot disambiguate them.
//
//  Android build of `AttributedString(FAHTML:)`. WebKit's HTML importer
//  (`NSAttributedString(data:.html)`) doesn't exist here — and nothing needs to
//  replace it, because Compose parses HTML itself. So the markup is normalised into
//  the subset it understands, with FA's theme restated into it, and carried,
//  verbatim, to `HTMLView`. The signature matches the Apple version so FAKit domain
//  code is unchanged.
//

#if os(Android)

import Foundation

extension AttributedString {
    @MainActor
    public init(FAHTML: String) async throws {
        let token = signposter.beginInterval("AttributedString.init(FAHTML:)")
        defer { signposter.endInterval("AttributedString.init(FAHTML:)", token) }

        let theme = FATheme.current
        // Off the main actor, so a page's comments convert concurrently.
        let fragments = try await Task.detached {
            try FAHTMLNormalizer.fragments(of: FAHTML, theme: theme)
        }.value
        self = AttributedString(faHTMLFragments: fragments)
    }
}

#endif
