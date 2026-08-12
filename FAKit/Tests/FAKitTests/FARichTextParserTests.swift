//
//  FARichTextParserTests.swift
//  FAKitTests
//
//  Drives the parser from the same captured pages the FAPages suites use, so the
//  markup under test is real FA output rather than a hand-written approximation.
//

import Foundation
import Testing
@testable import FAKit
@testable import FAPages

private func parse(_ html: String) throws -> AttributedString {
    try FARichTextParser.attributedString(fromFAHTML: html)
}

private extension AttributedString {
    var plainText: String { String(characters) }

    /// The style of the first run whose text contains `substring`.
    func style(containing substring: String) -> FAInlineStyle? {
        for run in runs where String(self[run.range].characters).contains(substring) {
            return run.faInline ?? .default
        }
        return nil
    }

    var images: [FAInlineImage] {
        runs.compactMap { $0.faImage }
    }
}

private extension Array<FARichTextBlock> {
    func first(containing substring: String) -> FARichTextBlock? {
        first { String($0.text.characters).contains(substring) }
    }
}

// MARK: - Structure from a real user profile

/// terriniss's profile is the densest bbcode in the fixture corpus: a centred `<code>`
/// wrapper holding `bbcode_h4`, `bbcode_hr`, `bbcode_b`, `bbcode_u`, `bbcode_sub`,
/// inline `style="color:"` spans and `.iconusername` avatars.
private func terrinissDescription() throws -> AttributedString {
    let data = testData("www.furaffinity.net:user:terriniss.html")
    let url = try #require(URL(string: "https://www.furaffinity.net/user/terriniss"))
    let page = try FAUserPage(data: data, url: url)
    return try parse(page.htmlDescription.selfContainedFAHtmlUserDescription)
}

struct FARichTextParserTests {
    @Test
    func inlineStyles() throws {
        let text = try terrinissDescription()

        #expect(text.style(containing: "Terriniss.")?.bold == true)
        #expect(text.style(containing: "My second account, for YCHes")?.underline == true)

        let sub = try #require(text.style(containing: "My main job here is creating"))
        #expect(sub.baseline == .sub)
        #expect(sub.sizeScale < 1)

        // <span class="bbcode" style="color: #C92A2A;">▸▹</span>
        #expect(text.style(containing: "▸▹")?.colorARGB == 0xFFC9_2A2A)
        // Plain body text keeps the theme's colour rather than a literal one.
        #expect(text.style(containing: "28 y.o.")?.colorARGB == nil)
        #expect(text.style(containing: "28 y.o.")?.bold == false)
    }

    @Test
    func blockStructure() throws {
        let blocks = try terrinissDescription().faBlocks

        // The whole profile sits in <code class="bbcode bbcode_center">.
        #expect(blocks.allSatisfy { $0.block.alignment == .center })

        let heading = try #require(blocks.first(containing: "𝙃𝙖𝙫𝙚 𝙖 𝙣𝙞𝙘𝙚 𝙙𝙖𝙮"))
        #expect(heading.block.kind == .heading(level: 4))

        #expect(blocks.contains { $0.block.kind == .rule })

        // Block indices are unique and ordered, so adjacent blocks never merge.
        #expect(blocks.map(\.block.index) == Array(0..<blocks.count))
    }

    @Test
    func inlineAvatarImages() throws {
        let text = try terrinissDescription()
        let avatars = text.images

        #expect(avatars.count > 3)
        #expect(avatars.allSatisfy { $0.isAvatar })
        #expect(avatars.contains {
            $0.url.absoluteString == "https://a.furaffinity.net/20250304/obsidianna.gif"
        })
        // Each avatar occupies exactly one object-replacement character…
        #expect(text.plainText.filter { $0 == "\u{FFFC}" }.count >= avatars.count)
        // …carried inside its <a class="iconusername"> link.
        let avatarRun = try #require(text.runs.first { $0.faImage != nil })
        #expect(avatarRun.link?.path.hasPrefix("/user/") == true)
    }

    @Test
    func linksSurviveForInAppNavigation() throws {
        let data = testData("www.furaffinity.net:view:49338772-nocomment.html")
        let url = try #require(URL(string: "https://www.furaffinity.net/view/49338772/"))
        let page = try FASubmissionPage(data: data, url: url)
        let text = try parse(page.htmlDescription.selfContainedFAHtmlSubmission)

        let links = text.runs.compactMap(\.link)
        #expect(links.contains { $0.absoluteString == "https://www.furaffinity.net/user/lil-maj" })
        #expect(text.plainText.contains("YCH"))
    }
}

// MARK: - Markup-level behaviour, driven by fragments taken from those same fixtures

struct FARichTextParserMarkupTests {
    /// The fragment FA wraps every centred description in.
    private static func centredFragment() throws -> String {
        let data = testData("www.furaffinity.net:user:terriniss.html")
        let url = try #require(URL(string: "https://www.furaffinity.net/user/terriniss"))
        return try FAUserPage(data: data, url: url).htmlDescription
    }

    @Test
    func brBecomesALineBreakInsideItsBlock() throws {
        let text = try parse(Self.centredFragment().selfContainedFAHtmlUserDescription)
        let paragraph = try #require(text.faBlocks.first(containing: "My name is"))
        // "My name is Terriniss." and "Briefly - Tira." are <br />-separated, so they
        // share one block instead of becoming two.
        #expect(String(paragraph.text.characters).contains("\n"))
        #expect(String(paragraph.text.characters).contains("Briefly"))
    }

    @Test
    func whitespaceCollapsesLikeInABrowser() throws {
        let text = try parse(Self.centredFragment().selfContainedFAHtmlUserDescription)
        let plain = text.plainText
        // Runs of source whitespace fold into one space…
        #expect(!plain.contains("  "))
        // …and a space stranded at the end of a line goes with the line break, which
        // matters in a centred block where it would shift the whole line.
        #expect(!plain.contains(" \n"))
        // Deliberate blank lines (<br /><br />) do survive.
        #expect(plain.contains("\n\n"))
    }

    @Test
    func blocksDoNotStartOrEndOnAStrayLineBreak() throws {
        let blocks = try parse(Self.centredFragment().selfContainedFAHtmlUserDescription)
            .faBlocks
        // FA separates its <hr>s from the surrounding text with <br />s. Those abut a
        // block boundary, where the renderer's own spacing already does the separating.
        #expect(blocks.allSatisfy { !String($0.text.characters).hasPrefix("\n") })
        #expect(blocks.allSatisfy { !String($0.text.characters).hasSuffix("\n") })
    }

    @Test
    func emptyAndUnknownMarkupDegradesToPlainText() throws {
        let blocks = try parse("<body><div></div><p>  </p><marquee>kept</marquee></body>").faBlocks
        #expect(blocks.count == 1)
        #expect(String(blocks[0].text.characters) == "kept")
        #expect(blocks[0].block.kind == .paragraph)
    }
}
