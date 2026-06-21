//
//  StoryDocumentTests.swift
//  FAKit
//
//  Created by Ceylo on 21/06/2026.
//

import Testing
import Foundation
import UIKit
@testable import FAKit

struct StoryDocumentTests {
    @Test
    func docxStory_extractsReadableText() throws {
        let attributed = try #require(StoryDocument.richText(from: testData("1781809267.botsu1x_prepared_with_the_fall_out___1_.docx"), filename: "story.docx"))
        let text = String(attributed.characters)

        #expect(text.hasPrefix("Sun setting overhead, a shimmer of glistening dread"))
        #expect(text.contains("Even the small sticks here can be used as tools for later."))
        // Paragraphs are preserved as line breaks.
        #expect(text.contains("\n"))
    }

    @Test
    func docxStory_preservesBoldOrItalic() throws {
        let attributed = try #require(StoryDocument.richText(from: testData("1781809267.botsu1x_prepared_with_the_fall_out___1_.docx"), filename: "story.docx"))
        #expect(hasTrait(.traitBold, in: attributed) || hasTrait(.traitItalic, in: attributed))
    }

    @Test
    func pdfStory_extractsReadableText() throws {
        let attributed = try #require(StoryDocument.richText(from: testData("1781832277.vixyyfox_3000_-redfurythings.pdf"), filename: "story.pdf"))
        let text = String(attributed.characters)

        #expect(text.contains("Redfurythings"))
        #expect(text.contains("by: Vixyy Fox"))
        #expect(text.contains("I prefer being in my human form."))
    }

    @Test
    func plainTextFile_isReturnedAsIs() throws {
        let attributed = try #require(StoryDocument.richText(from: Data("Hello world".utf8), filename: "story.txt"))
        #expect(String(attributed.characters) == "Hello world")
    }

    @Test
    func unsupportedFormat_returnsNil() {
        #expect(StoryDocument.richText(from: Data("anything".utf8), filename: "story.bin") == nil)
    }

    /// True if any run carries the given symbolic trait.
    private func hasTrait(_ trait: UIFontDescriptor.SymbolicTraits, in attributed: AttributedString) -> Bool {
        let ns = NSAttributedString(attributed)
        var found = false
        ns.enumerateAttribute(.font, in: NSRange(location: 0, length: ns.length)) { value, _, stop in
            if let font = value as? UIFont, font.fontDescriptor.symbolicTraits.contains(trait) {
                found = true
                stop.pointee = true
            }
        }
        return found
    }
}
