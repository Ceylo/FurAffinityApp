//
//  FAHTMLNormalizerTests.swift
//  FAKitTests
//
//  HTML→HTML assertions, driven by the same captured pages the parser suites use so the
//  markup under test is real FA output rather than a hand-written approximation.
//

import Foundation
import SwiftSoup
import Testing
@testable import FAKit
@testable import FAPages

private func normalize(_ html: String) throws -> FANormalizedHTML {
    try FAHTMLNormalizer.normalized(html)
}

/// terriniss's profile is the densest bbcode in the fixture corpus: a centred `<code>`
/// wrapper holding `bbcode_h4`, `bbcode_hr`, `bbcode_b`, `bbcode_u`, `bbcode_sub`,
/// inline `style="color:"` spans and `.iconusername` avatars.
private func terrinissDescription() throws -> String {
    let data = testData("www.furaffinity.net:user:terriniss.html")
    let url = try #require(URL(string: "https://www.furaffinity.net/user/terriniss"))
    return try FAUserPage(data: data, url: url)
        .htmlDescription
        .selfContainedFAHtmlUserDescription
}

// MARK: - Alignment

struct FAHTMLNormalizerAlignmentTests {
    @Test
    func centredCodeBecomesABlockThatFromHtmlCanAlign() throws {
        // FA compiles [center] to a class on <code>, which android.text.Html doesn't know.
        let source = try terrinissDescription()
        #expect(source.contains("<code class=\"bbcode bbcode_center\">"))

        let html = try normalize(source).html
        #expect(!html.contains("<code"))
        #expect(html.contains("text-align:center"))
    }

    @Test
    func physicalAlignmentValuesBecomeLogicalOnes() throws {
        // fromHtml reads start/center/end, never left/right, and never align="…".
        let html = try normalize("""
        <code class="bbcode_left">L</code>
        <code class="bbcode_right">R</code>
        <div style="text-align: left">SL</div>
        <div style="text-align: RIGHT">SR</div>
        <div align="center">A</div>
        """).html

        #expect(html.contains("text-align:start"))
        #expect(html.contains("text-align:end"))
        #expect(!html.contains("text-align:left"))
        #expect(!html.contains("text-align:right"))
        #expect(html.contains("text-align:center"))
    }

    @Test
    func alignedBlockTagsKeepTheirOwnMeaning() throws {
        // Renaming this to <div> would cost the heading its size and weight.
        let html = try normalize("<h4 class=\"bbcode_center\">Heading</h4>").html
        #expect(html.contains("<h4"))
        #expect(html.contains("text-align:center"))
    }

    @Test
    func anExistingStyleSurvivesAlongsideTheAlignment() throws {
        let html = try normalize("<code class=\"bbcode_center\" style=\"color: #C92A2A\">x</code>").html
        #expect(html.contains("color:#c92a2a"))
        #expect(html.contains("text-align:center"))
    }

    @Test
    func unalignedMarkupIsLeftAlone() throws {
        let html = try normalize("<p>plain</p>").html
        #expect(!html.contains("text-align"))
    }
}

// MARK: - Rules

struct FAHTMLNormalizerRuleTests {
    /// Serialised sibling tags at the top level of the normalised markup.
    private func topLevelTags(_ html: String) throws -> [String] {
        let root = try #require(try SwiftSoup.parse(html).body())
        return root.children().map { $0.tagName().lowercased() }
    }

    @Test
    func everyRuleEndsUpAtTheTopLevel() throws {
        let source = try terrinissDescription()
        // FA nests its rules inside the wrapper that carries the alignment.
        #expect(source.contains("bbcode_hr"))

        let normalized = try normalize(source)
        let root = try #require(try SwiftSoup.parse(normalized.html).body())
        let rules = try root.getElementsByTag("hr")
        #expect(rules.count == 3)
        #expect(rules.allSatisfy { $0.parent() === root })
    }

    @Test
    func splittingKeepsTheAlignmentOnBothSides() throws {
        let html = try normalize("""
        <code class="bbcode_center">before<hr>after</code>
        """).html
        let tags = try topLevelTags(html)
        #expect(tags == ["div", "hr", "div"])

        let root = try #require(try SwiftSoup.parse(html).body())
        let blocks = root.children().array().filter { $0.tagName().lowercased() == "div" }
        // Without the split the second half would have no opening tag, and so no
        // alignment, once the renderer cuts the string at the rule.
        #expect(try blocks.allSatisfy { try $0.attr("style").contains("center") })
        #expect(try blocks.first?.text() == "before")
        #expect(try blocks.last?.text() == "after")
    }

    @Test
    func aWrapperHoldingOnlyARuleDoesNotLeaveAnEmptyBlock() throws {
        let html = try normalize("<div><hr></div>").html
        #expect(try topLevelTags(html) == ["hr"])
    }

    @Test
    func consecutiveRulesEachSurvive() throws {
        let html = try normalize("<div>a<hr><hr>b</div>").html
        #expect(try topLevelTags(html) == ["div", "hr", "hr", "div"])
    }

    @Test
    func aRuleNestedTwoDeepIsLiftedAllTheWay() throws {
        let html = try normalize("<div class=\"bbcode_center\"><p>a<hr>b</p></div>").html
        let root = try #require(try SwiftSoup.parse(html).body())
        #expect(try root.getElementsByTag("hr").allSatisfy { $0.parent() === root })
    }
}

// MARK: - Images

struct FAHTMLNormalizerImageTests {
    @Test
    func imagesAreCollectedInDocumentOrder() throws {
        let normalized = try normalize(try terrinissDescription())

        #expect(normalized.images.count == 13)
        // Each stays in the markup, where fromHtml turns it into one U+FFFC placeholder.
        let root = try #require(try SwiftSoup.parse(normalized.html).body())
        #expect(try root.getElementsByTag("img").count == normalized.images.count)

        #expect(normalized.images.first?.url.absoluteString
            == "https://a.furaffinity.net/20250304/vampireknightlampleftplz.gif")
        #expect(normalized.images.contains {
            $0.url.absoluteString == "https://a.furaffinity.net/20250304/obsidianna.gif"
        })
    }

    @Test
    func avatarsAreRecognisedFromTheLinkThatCarriesThem() throws {
        // FA marks .iconusername on the <a>, never on the <img> inside it.
        let images = try normalize("""
        <a href="/user/terriniss" class="iconusername"><img src="//a.furaffinity.net/x.gif"></a>
        <img src="//a.furaffinity.net/smilie.gif" width="19" height="19">
        """).images

        #expect(images.count == 2)
        #expect(images[0].isAvatar)
        #expect(!images[1].isAvatar)
        #expect(images[1].width == 19)
        #expect(images[1].height == 19)
    }

    @Test
    func alignOnAnImageIsNotReadAsTextAlignment() throws {
        // FA writes `<img align="middle">` on every inline avatar. That is *vertical*
        // alignment; treating it as text alignment turns the image into a block and
        // loses it, placeholder and all.
        let normalized = try normalize("<img src=\"//a.furaffinity.net/x.gif\" align=\"middle\">")
        #expect(normalized.images.count == 1)
        #expect(normalized.html.contains("<img"))
    }

    @Test
    func aSourcelessImageIsSkippedRatherThanCountedAsAPlaceholder() throws {
        // fromHtml emits no U+FFFC for one of these, so counting it would shift every
        // later image onto the wrong placeholder.
        #expect(try normalize("<img alt=\"broken\">").images.isEmpty)
    }
}

// MARK: - What is deliberately left alone

struct FAHTMLNormalizerPassthroughTests {
    @Test
    func semanticMarkupFromHtmlAlreadyUnderstandsIsUntouched() throws {
        let html = try normalize(try terrinissDescription()).html
        for tag in ["<strong", "<sub", "<h4", "<a ", "<br"] {
            #expect(html.contains(tag), "\(tag) should survive normalisation")
        }
        // Literal colours ride on spans, which fromHtml reads directly.
        #expect(html.contains("color: #C92A2A") || html.contains("color:#c92a2a"))
    }

    @Test
    func absoluteURLsFromFixingLinksSurvive() throws {
        // String+FA's `fixingLinks` runs before this and must not be undone.
        let html = try normalize(try terrinissDescription()).html
        #expect(html.contains("https://a.furaffinity.net/"))
        #expect(!html.contains("src=\"//"))
    }

    @Test
    func emptyAndUnknownMarkupSurvivesAsText() throws {
        #expect(try normalize("").html.isEmpty)
        #expect(try normalize("<marquee>kept</marquee>").html.contains("kept"))
    }
}
