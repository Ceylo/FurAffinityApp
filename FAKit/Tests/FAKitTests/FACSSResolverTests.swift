//
//  FACSSResolverTests.swift
//  FAKitTests
//
//  FA's bundled dark theme applied to captured pages, as the Android renderer receives
//  them: through `FAHTMLNormalizer`.
//

import Foundation
import SwiftSoup
import Testing
@testable import FAKit
@testable import FAPages

private func darkTheme() async -> FAStylesheet {
    FAStylesheet(css: await CSSInliner.shared.fallbackCSS(for: .dark))
}

/// terriniss's profile, in the wrapper submissions and journals get — the one that
/// carries `.user-submitted-links`.
private func terrinissDescription() throws -> String {
    let data = testData("www.furaffinity.net:user:terriniss.html")
    let url = try #require(URL(string: "https://www.furaffinity.net/user/terriniss"))
    return try FAUserPage(data: data, url: url)
        .htmlDescription
        .selfContainedFAHtmlSubmission
}

private func body(of html: String) throws -> Element {
    let document = try SwiftSoup.parse(html)
    return try #require(document.body())
}

struct FACSSResolverTests {
    @Test
    func headingTakesTheThemeColour() async throws {
        let html = try FAHTMLNormalizer.normalized(terrinissDescription(), stylesheet: await darkTheme()).html
        let heading = try #require(try body(of: html).select("h4.bbcode_h4").first())
        #expect(try heading.child(0).outerHtml().hasPrefix(#"<span style="color:#add8f5">"#))
    }

    @Test
    func quoteIsItalicAndItsNameBold() async throws {
        let html = try FAHTMLNormalizer.normalized("""
        <span class="bbcode bbcode_quote"><span class="bbcode_quote_name">someone wrote:</span>quoted</span>
        """, stylesheet: await darkTheme()).html
        let quote = try #require(try body(of: html).select(".bbcode_quote").first())
        #expect(try quote.child(0).tagName() == "i")
        let name = try #require(try quote.select(".bbcode_quote_name").first())
        #expect(try name.child(0).tagName() == "b")
    }

    @Test
    func spoilerIsLeftVisible() async throws {
        let source = #"<span class="bbcode bbcode_spoiler">hidden</span>"#
        let html = try FAHTMLNormalizer.normalized(source, stylesheet: await darkTheme()).html
        let spoiler = try #require(try body(of: html).select(".bbcode_spoiler").first())
        #expect(spoiler.children().isEmpty())
        #expect(!html.contains("transparent"))
    }

    @Test
    func inlineStyleBeatsTheSheet() async throws {
        // terriniss colours her own text with `style="color: …"`; the sheet must not
        // paint over it, even where its rule matches the same element.
        let source = #"<h4 class="bbcode bbcode_h4" style="color: #C92A2A;">Heading</h4>"#
        let html = try FAHTMLNormalizer.normalized(source, stylesheet: await darkTheme()).html
        #expect(!html.contains("#add8f5"))
        #expect(html.contains("#C92A2A"))
    }

    @Test
    func linksKeepTheAppTintButTakeTheWeight() async throws {
        // `.user-submitted-links a` sets both a colour and weight 600.
        let html = try FAHTMLNormalizer.normalized(terrinissDescription(), stylesheet: await darkTheme()).html
        let root = try body(of: html)
        #expect(!html.contains("#d0e6f5"))
        let links = try root.select("a").array().filter { !$0.hasClass("iconusername") }
        try #require(!links.isEmpty)
        #expect(try links.allSatisfy { try $0.child(0).tagName() == "b" })
    }

    @Test
    func statefulAndPageSelectorsAreIgnored() {
        let resolver = FACSSResolver(stylesheet: """
        .a:hover { color: red }
        #b .c { color: red }
        body .d { color: red }
        @media (max-width: 10px) { .e { color: red } }
        /* .f { color: red } */
        .g { color: red; margin: 0 }
        .h { margin: 0 }
        """)
        #expect(resolver.rules.map(\.selector) == [".g"])
    }

    @Test
    func cascadeHonoursImportanceThenSpecificityThenOrder() throws {
        let resolver = FACSSResolver(stylesheet: """
        .x { color: #111111 !important }
        span.x { color: #222222 }
        .x { color: #333333 }
        .y { color: #444444 }
        span.y { color: #555555 }
        """)
        let root = try body(of: #"<span class="x">a</span><span class="y">b</span>"#)
        try resolver.apply(to: root)
        let html = try root.html()
        #expect(html.contains("color:#111111"))
        #expect(html.contains("color:#555555"))
    }
}

struct FACSSResolverPrecedenceTests {
    private func resolve(_ css: String, _ html: String) throws -> String {
        let root = try #require(try SwiftSoup.parse(html).body())
        try FACSSResolver(stylesheet: css).apply(to: root)
        return try root.html()
    }

    @Test
    func anImportantInlineStyleBeatsAnImportantRule() throws {
        let html = try resolve(
            ".x { color: #111111 !important }",
            #"<span class="x" style="color: #222222 !important">a</span>"#
        )
        #expect(!html.contains("#111111"))
    }

    @Test
    func anInlineStyleFromHtmlIgnoresIsRestated() throws {
        // `android.text.Html` reads `color` from `style` on <span> and <p> only.
        let html = try resolve(".x { color: #111111 }", #"<div class="x" style="color: #222222">a</div>"#)
        #expect(html.contains(#"<span style="color:#222222">a</span>"#))
        #expect(!html.contains("#111111"))
    }

    @Test
    func aCombinatorCharacterInsideAnAttributeSelectorDoesNotSplitIt() throws {
        let html = try resolve("a[rel~=nofollow] { font-weight: bold }", #"<a rel="nofollow" href="x">a</a>"#)
        #expect(html.contains("<b>a</b>"))
    }

    @Test
    func aDotInsideAnAttributeValueIsNoClass() {
        #expect(FACSSResolver.specificity(of: #"a[href$=".png"]"#) == FACSSResolver.specificity(of: "a.x"))
    }
}
