//
//  AttributedString+FA.swift
//  
//
//  Created by Ceylo on 11/04/2022.
//

import Foundation
import UIKit

extension AttributedString {
    @MainActor // needed for NSAttributedString from HTML data which calls WebKit which isn't thread-safe
    public init(FAHTML: String) async throws {
        let token = signposter.beginInterval("AttributedString.init(FAHTML:)")
        defer { signposter.endInterval("AttributedString.init(FAHTML:)", token) }
        let theme = FATheme(style: UITraitCollection.current.userInterfaceStyle)
        
        let data = try await FAHTML
            .using(theme: theme)
            .inliningCSS()
            .inliningImages()
            .data(using: .utf8)
            .unwrap()
        let nsattrstr = try NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: NSNumber(value: String.Encoding.utf8.rawValue)
            ],
            documentAttributes: nil
        )
        .rebuildingSystemFonts()

        self = AttributedString(nsattrstr)
            .transformingAttributes(\.foregroundColor) { foregroundColor in
                if foregroundColor.value == nil {
                    foregroundColor.value = .primary
                }
            }
            .transformingAttributes(\.font) { font in
                font.value = .body
            }
    }
}

private extension NSAttributedString {
    /// Rebuilds each font as a system font of the same size and bold/italic traits.
    ///
    /// The HTML importer names its fonts privately (`.SFUI-Regular`) without the
    /// `NSCTFontUIUsageAttribute` of a real system font. Such name-based references fail to
    /// re-resolve during a trait-collection change (e.g. dismissing a sheet over the text),
    /// so glyphs silently fall back to Times — plain text turns serif on the round-trip.
    /// `UIFont.systemFont(ofSize:)` restores the UI-usage attribute and resolves reliably.
    func rebuildingSystemFonts() -> NSAttributedString {
        let mutable = NSMutableAttributedString(attributedString: self)
        let fullRange = NSRange(location: 0, length: mutable.length)
        mutable.enumerateAttribute(.font, in: fullRange) { value, range, _ in
            guard let font = value as? UIFont else { return }
            var rebuilt = UIFont.systemFont(ofSize: font.pointSize)
            let traits = font.fontDescriptor.symbolicTraits.intersection([.traitBold, .traitItalic])
            if !traits.isEmpty,
               let descriptor = rebuilt.fontDescriptor.withSymbolicTraits(traits) {
                rebuilt = UIFont(descriptor: descriptor, size: font.pointSize)
            }
            mutable.addAttribute(.font, value: rebuilt, range: range)
        }
        return mutable
    }
}
