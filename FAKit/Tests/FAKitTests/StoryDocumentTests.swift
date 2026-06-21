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
    func pdfStory_separatesTitleBlockAndParagraphs() throws {
        let attributed = try #require(StoryDocument.richText(from: testData("1781832277.vixyyfox_3000_-redfurythings.pdf"), filename: "story.pdf"))
        let text = String(attributed.characters)

        // Short title lines stay on their own lines instead of running together.
        #expect(text.contains("(30)\nRedfurythings"), "title block not split: \(text.prefix(120))")
        #expect(text.contains("(#Twelve Manny)\nI prefer"), "title/body not split: \(text.prefix(200))")
        // A real paragraph break inside the body is preserved.
        #expect(text.contains("in human form.\nThis morning"), "paragraph break missing")
        // The run-on bug (joining the break with a space) must not recur.
        #expect(!text.contains("human form. This morning"), "paragraphs ran on")
    }

    @Test
    func pdfStory_reflowsSoftWrappedLines() throws {
        let attributed = try #require(StoryDocument.richText(from: testData("1781832277.vixyyfox_3000_-redfurythings.pdf"), filename: "story.pdf"))
        let lines = String(attributed.characters).split(separator: "\n", omittingEmptySubsequences: false)

        // Before reflow every physical PDF line was its own line (~40 chars);
        // after reflow a paragraph collapses into one long line.
        let longest = lines.map(\.count).max() ?? 0
        #expect(longest > 200, "expected a reflowed paragraph, longest line was \(longest) chars")
    }

    @Test
    func pdfStory_preservesHeadingAndEmphasis() throws {
        let attributed = try #require(StoryDocument.richText(from: testData("1781832277.vixyyfox_3000_-redfurythings.pdf"), filename: "story.pdf"))
        let ns = NSAttributedString(attributed)

        var distinctSizes = Set<CGFloat>()
        var emphasised = false
        ns.enumerateAttribute(.font, in: NSRange(location: 0, length: ns.length)) { value, _, _ in
            guard let font = value as? UIFont else { return }
            distinctSizes.insert(font.pointSize)
            if !font.fontDescriptor.symbolicTraits.isDisjoint(with: [.traitBold, .traitItalic]) {
                emphasised = true
            }
        }
        // Heading vs body sizes survive, and at least one run is bold/italic.
        #expect(distinctSizes.count > 1, "expected varying font sizes, got \(distinctSizes.sorted())")
        #expect(emphasised)
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
