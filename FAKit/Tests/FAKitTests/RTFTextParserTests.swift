//
//  RTFTextParserTests.swift
//  FAKit
//
//  Created by Ceylo on 04/11/2026.
//

import Testing
import Foundation
@testable import FAKit

struct RTFTextParserTests {
    private func paragraphs(_ rtf: String) throws -> [StoryParagraph] {
        let text = try #require(RTFTextParser.text(from: Data(rtf.utf8)))
        return StoryParagraph.paragraphs(from: text, bodyPointSize: 17)
    }

    @Test
    func readsParagraphsTraitsAndSizes() throws {
        let paragraphs = try paragraphs(
            #"{\rtf1\ansi\ansicpg1252{\fonttbl{\f0 Times;}}{\colortbl;\red0\green0\blue0;}"#
                + #"\pard\qc\b\fs32 Title\b0\par\pard\fs24 Plain \i italic\i0  end.\par}"#
        )
        #expect(paragraphs.map(\.text) == ["Title", "Plain italic end."])
        #expect(paragraphs[0].centered)
        #expect(paragraphs[0].runs.map(\.font) == [StoryFont(size: 16, bold: true)])
        #expect(!paragraphs[1].centered)
        #expect(paragraphs[1].runs.map(\.font.italic) == [false, true, false])
        #expect(paragraphs[1].runs.map(\.font.size) == [12, 12, 12])
    }

    @Test
    func decodesEscapesAndUnicode() throws {
        let paragraphs = try paragraphs(
            #"{\rtf1\ansi\ansicpg1252\uc1 a\tab caf\'e9 \u8212? \'93q\'94 \{x\} \u-10179?\u-8704?\line next}"#
        )
        #expect(paragraphs.map(\.text) == ["a\tcafé — “q” {x} 😀", "next"])
    }

    @Test
    func skipsDestinations() throws {
        let paragraphs = try paragraphs(
            #"{\rtf1{\*\generator Writer;}{\info{\title Hidden}}{\stylesheet{\s0 Normal;}}Shown "#
                + #"{\field{\fldinst HYPERLINK "https://example.com"}{\fldrslt link}}}"#
        )
        #expect(paragraphs.map(\.text) == ["Shown link"])
    }

    @Test
    func rejectsNonRTF() {
        #expect(RTFTextParser.text(from: Data("plain text".utf8)) == nil)
    }
}
