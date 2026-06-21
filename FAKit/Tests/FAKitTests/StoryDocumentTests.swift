//
//  StoryDocumentTests.swift
//  FAKit
//
//  Created by Ceylo on 21/06/2026.
//

import Testing
import Foundation
import UIKit
import PDFKit
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

        // Title lines each stay on their own line.
        #expect(text.contains("(30)\nRedfurythings"), "title block not split: \(text.prefix(120))")
        // The title block ends and the body starts a new paragraph.
        #expect(text.contains("(#Twelve Manny)\nI prefer"), "title/body not split: \(text.prefix(200))")
        // A real paragraph break inside the body is preserved.
        #expect(text.contains("in human form.\nThis morning"), "paragraph break missing")
        // The run-on bug (joining the break with a space) must not recur.
        #expect(!text.contains("human form. This morning"), "paragraphs ran on")
    }

    @Test
    func pdfStory_keepsEveryWord() throws {
        let data = testData("1781832277.vixyyfox_3000_-redfurythings.pdf")
        let attributed = try #require(StoryDocument.richText(from: data, filename: "story.pdf"))

        // Source words: everything PDFKit reports across the pages.
        let document = try #require(PDFDocument(data: data))
        var source = ""
        for index in 0..<document.pageCount {
            source += (document.page(at: index)?.attributedString?.string ?? "") + "\n"
        }

        // The reflow joins lines and de-hyphenates, but it must never drop a word.
        var remaining: [String: Int] = [:]
        for word in words(in: String(attributed.characters)) { remaining[word, default: 0] += 1 }

        var missing: [String] = []
        for word in words(in: source) {
            if let count = remaining[word], count > 0 { remaining[word] = count - 1 }
            else { missing.append(word) }
        }
        #expect(missing.isEmpty, "words dropped during reflow: \(missing)")
    }

    @Test
    func pdfStory_doesNotBreakIndentedSoftWraps() throws {
        let attributed = try #require(StoryDocument.richText(from: testData("1781832277.vixyyfox_3000_-redfurythings.pdf"), filename: "story.pdf"))
        let text = String(attributed.characters)

        // Short tail lines that drift right (justified text) used to be mistaken for
        // paragraph starts; they must stay joined to the line they continue.
        #expect(text.contains("but there wasn’t any answer"), "indented soft wrap broke the sentence")
        #expect(!text.contains("but there\nwasn’t"))
        #expect(!text.contains("but there\u{2028}wasn’t"))
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
    func pdfStory_doesNotSplitContractionsAtCurlyQuotes() throws {
        let attributed = try #require(StoryDocument.richText(from: testData("1751926678.amber-calliope_lima_nox_ch0-1__2_.pdf"), filename: "story.pdf"))
        let text = String(attributed.characters)

        // PDFKit splits these at the curly apostrophe (a separate font run); the reflow
        // must rejoin the fragments so contractions stay whole.
        #expect(text.contains("it’s scrutinous"), "contraction split: \(text.prefix(500))")
        #expect(text.contains("I don’t entirely find"))
        #expect(text.contains("There’s a light coming"))
        #expect(text.contains("It’s cold in this room"))
        // The broken forms must not survive.
        #expect(!text.contains("it’\ns"))
        #expect(!text.contains("There’\ns"))
        #expect(!text.contains("don\n’t"))
    }

    @Test
    func pdfStory_restoresFirstLineIndentTabs() throws {
        let attributed = try #require(StoryDocument.richText(from: testData("1642368831.typhin_princess_tells_her_story.pdf"), filename: "story.pdf"))
        let text = String(attributed.characters)

        // This PDF indents the first line of each paragraph (positionally, not as a tab
        // character); restore it as a leading tab so paragraphs read as in the source.
        #expect(text.contains("\n\tThe wizard Elimaio"), "missing paragraph indent: \(String(text.prefix(400)))")
        #expect(text.contains("\n\tOnce we were alone"))
        // The justified body's noisy geometry must not produce spurious breaks: clauses
        // split at curly quotes stay joined, as do plain soft wraps.
        #expect(text.contains("my new “normal”, but I was wrong."))
        #expect(text.contains("the “experiments”. And yes,"))
        #expect(text.contains("as they disappeared once the door"))
    }

    @Test
    func pdfStory_blockStyleDocumentGetsNoIndentTabs() throws {
        // A document that separates paragraphs by spacing (not first-line indents) must
        // not gain spurious tabs from the noisy per-character geometry.
        let attributed = try #require(StoryDocument.richText(from: testData("1781832277.vixyyfox_3000_-redfurythings.pdf"), filename: "story.pdf"))
        #expect(!String(attributed.characters).contains("\t"))
    }

    @Test
    func pdfStory_respectsCenteredTitleAlignment() throws {
        let attributed = try #require(StoryDocument.richText(from: testData("1751926678.amber-calliope_lima_nox_ch0-1__2_.pdf"), filename: "story.pdf"))
        let ns = NSAttributedString(attributed)
        let titleRange = (ns.string as NSString).range(of: "LIMA NOX - BOXES")
        try #require(titleRange.location != NSNotFound)

        var centered = false
        ns.enumerateAttribute(.paragraphStyle, in: titleRange) { value, _, _ in
            if let style = value as? NSParagraphStyle, style.alignment == .center { centered = true }
        }
        #expect(centered, "centered title lost its alignment")
    }

    @Test
    func pdfStory_preservesEmbeddedImages() throws {
        let attributed = try #require(StoryDocument.richText(from: testData("1751926678.amber-calliope_lima_nox_ch0-1__2_.pdf"), filename: "story.pdf"))
        let ns = NSAttributedString(attributed)

        var images = 0
        ns.enumerateAttribute(.attachment, in: NSRange(location: 0, length: ns.length)) { value, _, _ in
            if let attachment = value as? NSTextAttachment, attachment.image != nil { images += 1 }
        }
        #expect(images >= 1, "expected inline images, found \(images)")
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

    /// Splits text into words, trimming surrounding punctuation and dropping empties.
    private func words(in text: String) -> [String] {
        text.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
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
