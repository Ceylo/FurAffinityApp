//
//  StoryParagraphsTests.swift
//  FAKit
//
//  Created by Ceylo on 04/11/2026.
//

import Testing
import Foundation
@testable import FAKit

struct StoryParagraphsTests {
    @Test
    func plainText_keepsBlankLinesAsEmptyParagraphs() throws {
        let paragraphs = try #require(StoryDocument.paragraphs(from: Data("One\n\nTwo".utf8), filename: "story.txt"))
        #expect(paragraphs.map(\.text) == ["One", "", "Two"])
        #expect(paragraphs[1].runs.isEmpty)
        #expect(paragraphs.dominantFontSize == StoryDocument.bodyPointSize)
    }

    @Test
    func unsupportedFormat_returnsNil() {
        #expect(StoryDocument.paragraphs(from: Data("anything".utf8), filename: "story.bin") == nil)
    }

    @Test
    func neutralText_splitsAtNewlinesAndMergesEqualRuns() {
        let bold = StoryFont(size: 20, bold: true)
        let text = NSMutableAttributedString(string: "")
        text.append(NSAttributedString(string: "Ti", attributes: [.storyFont: bold, .storyCentered: true]))
        text.append(NSAttributedString(string: "tle", attributes: [.storyFont: bold, .storyCentered: true]))
        text.append(NSAttributedString(string: "\nplain "))
        text.append(NSAttributedString(string: "it", attributes: [.storyFont: StoryFont(size: 17, italic: true)]))
        text.append(NSAttributedString(string: "\n"))
        text.append(NSAttributedString(string: "\u{FFFC}", attributes: [.storyImage: Data([1, 2])]))

        let paragraphs = StoryParagraph.paragraphs(from: text, bodyPointSize: 17)
        #expect(paragraphs.count == 3)
        #expect(paragraphs[0].runs == [StoryRun(text: "Title", font: bold)])
        #expect(paragraphs[0].centered)
        #expect(paragraphs[1].runs.map(\.text) == ["plain ", "it"])
        #expect(!paragraphs[1].centered)
        #expect(paragraphs[2].image == Data([1, 2]))
        #expect(paragraphs[2].runs.isEmpty)
    }

    #if !os(Android)
    @Test
    func docx_paragraphsKeepTextAndTraits() throws {
        let paragraphs = try #require(StoryDocument.paragraphs(
            from: testData("1781809267.botsu1x_prepared_with_the_fall_out___1_.docx"),
            filename: "story.docx"
        ))
        let first = try #require(paragraphs.first)
        #expect(first.text.hasPrefix("Sun setting overhead, a shimmer of glistening dread"))
        #expect(paragraphs.count > 1)
        #expect(paragraphs.flatMap(\.runs).contains { $0.font.bold || $0.font.italic })
    }

    @Test
    func pdf_paragraphsKeepCenteringImagesAndIndents() throws {
        let lima = try #require(StoryDocument.paragraphs(
            from: testData("1751926678.amber-calliope_lima_nox_ch0-1__2_.pdf"),
            filename: "story.pdf"
        ))
        let title = try #require(lima.first { $0.text == "LIMA NOX - BOXES" })
        #expect(title.centered)
        #expect(lima.contains { $0.image != nil })

        let typhin = try #require(StoryDocument.paragraphs(
            from: testData("1642368831.typhin_princess_tells_her_story.pdf"),
            filename: "story.pdf"
        ))
        #expect(typhin.contains { $0.text.hasPrefix("\tThe wizard Elimaio") })
    }

    @Test
    func pdf_dominantSizeIsTheBody() throws {
        let paragraphs = try #require(StoryDocument.paragraphs(
            from: testData("1781832277.vixyyfox_3000_-redfurythings.pdf"),
            filename: "story.pdf"
        ))
        let body = try #require(paragraphs.dominantFontSize)
        #expect(paragraphs.flatMap(\.runs).contains { $0.font.size > body })
    }
    #endif
}
