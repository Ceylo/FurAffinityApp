//
//  AttributedString+FA+Android.swift
//  FAKit
//
//  Android build of `AttributedString(FAHTML:)`. WebKit's HTML importer
//  (`NSAttributedString(data:.html)`) doesn't exist here — and nothing needs to
//  replace it, because Compose parses HTML itself. So the markup is normalised into
//  the subset it understands and carried, verbatim, to `HTMLView`. The signature
//  matches the Apple version so FAKit domain code is unchanged.
//

#if os(Android)

import Foundation

extension AttributedString {
    @MainActor
    public init(FAHTML: String) async throws {
        let token = signposter.beginInterval("AttributedString.init(FAHTML:)")
        defer { signposter.endInterval("AttributedString.init(FAHTML:)", token) }

        self = AttributedString(faHTMLFragments: try FAHTMLNormalizer.normalized(FAHTML).fragments)
    }
}

#endif
