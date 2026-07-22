//
//  AttributedString+FA+Android.swift
//  FAKit
//
//  Android build of `AttributedString(FAHTML:)`. WebKit's HTML importer
//  (`NSAttributedString(data:.html)`) doesn't exist here, so the same small tag
//  set FA emits (b/i/u/s/a/br/img/span) is walked with SwiftSoup instead. The
//  signature matches the Apple version so FAKit domain code is unchanged.
//
//  Corelibs Foundation has no `InlinePresentationIntent`, so bold/italic/strike
//  carry no attribute yet; links and text layout are preserved.
//
#if os(Android)

import Foundation
import SwiftSoup

extension AttributedString {
    @MainActor
    public init(FAHTML: String) async throws {
        let token = signposter.beginInterval("AttributedString.init(FAHTML:)")
        defer { signposter.endInterval("AttributedString.init(FAHTML:)", token) }

        let document = try SwiftSoup.parse(FAHTML)
        var result = AttributedString()
        Self.appendFAHTML(node: document.body() ?? document, to: &result, link: nil)
        self = result
    }

    private static func appendFAHTML(node: Node, to string: inout AttributedString, link: URL?) {
        if let textNode = node as? TextNode {
            var run = AttributedString(textNode.getWholeText())
            if let link {
                run.link = link
            }
            string += run
            return
        }

        guard let element = node as? Element else { return }

        var link = link
        switch element.tagName().lowercased() {
        case "br":
            string += AttributedString("\n")
            return
        case "img":
            // Emoticons and inline images have no textual equivalent.
            return
        case "a":
            link = (try? element.attr("href"))?.faURL
        case "p", "div":
            if !string.characters.isEmpty {
                string += AttributedString("\n")
            }
        default:
            break
        }

        for child in element.getChildNodes() {
            appendFAHTML(node: child, to: &string, link: link)
        }
    }
}

private extension String {
    /// Absolute URL for an `href`, resolving FA's site-relative links.
    var faURL: URL? {
        if hasPrefix("//") { return URL(string: "https:" + self) }
        if hasPrefix("/") { return URL(string: "https://www.furaffinity.net" + self) }
        return URL(string: self)
    }
}

#endif
