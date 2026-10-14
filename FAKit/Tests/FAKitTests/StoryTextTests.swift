//
//  StoryTextTests.swift
//  FAKit
//
//  Created by Ceylo on 25/09/2026.
//

import Testing
import Foundation
@testable import FAKit

struct StoryTextTests {
    @Test
    func txt_splitsIntoLinesKeepingBlankOnes() throws {
        let data = Data("Chapter 1\n\nIt was dark.\r\nThen light.\n".utf8)
        let paragraphs = try #require(StoryText.paragraphs(from: data, filename: "story.txt"))
        #expect(paragraphs == ["Chapter 1", "", "It was dark.", "Then light.", ""])
    }

    @Test
    func md_isReadAsPlainText() throws {
        let data = Data("# Title\n*emphasis*".utf8)
        #expect(StoryText.paragraphs(from: data, filename: "STORY.MD") == ["# Title", "*emphasis*"])
    }

    @Test
    func otherFormats_areNotRead() {
        let data = Data("Hello".utf8)
        #expect(StoryText.text(from: data, filename: "story.docx") == nil)
        #expect(StoryText.text(from: data, filename: "story.pdf") == nil)
        #expect(StoryText.text(from: data, filename: "story") == nil)
    }

    @Test
    func nonUTF8Data_isNotRead() {
        #expect(StoryText.text(from: Data([0xFF, 0xFE, 0xFD]), filename: "story.txt") == nil)
    }
}
