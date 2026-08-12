//
//  AttributedString+FA+Android.swift
//  FAKit
//
//  Android build of `AttributedString(FAHTML:)`. WebKit's HTML importer
//  (`NSAttributedString(data:.html)`) doesn't exist here, so FA's markup is walked
//  with SwiftSoup instead and its styling carried in the custom `FAAttributes`
//  keys — see `FARichTextParser`. The signature matches the Apple version so FAKit
//  domain code is unchanged.
//

#if os(Android)

import Foundation

extension AttributedString {
    @MainActor
    public init(FAHTML: String) async throws {
        let token = signposter.beginInterval("AttributedString.init(FAHTML:)")
        defer { signposter.endInterval("AttributedString.init(FAHTML:)", token) }

        self = try FARichTextParser.attributedString(fromFAHTML: FAHTML)
    }
}

#endif
