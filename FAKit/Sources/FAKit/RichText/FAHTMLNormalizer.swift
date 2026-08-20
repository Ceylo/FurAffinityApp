//
//  FAHTMLNormalizer.swift
//  FAKit
//
//  Rewrites FA's markup into the subset Compose's `AnnotatedString.fromHtml` understands,
//  so the Android renderer can hand HTML straight to the platform instead of carrying a
//  parsed attribute vocabulary across the bridge.
//
//  Almost all of FA's `bbcode_*` classes ride on a tag that already means the same thing
//  (`bbcode_b` on `<strong>`, `bbcode_i` on `<i>`, `bbcode_hr` on `<hr>`…), which
//  `android.text.Html` handles unaided. Only three things need rewriting:
//
//  1. `[left]`/`[center]`/`[right]`, which FA compiles to a class on `<code>` — a tag
//     `android.text.Html` does not recognise at all. Alignment survives only as
//     `style="text-align:…"` on a *block* element, and only as `start`/`center`/`end`.
//  2. `<hr>`, which is dropped without even a line break. Hoisting every rule to a direct
//     child of the root lets the renderer split there and draw its own divider, without
//     the string surgery having to reason about nesting.
//  3. `<img>`, which survives as a bare U+FFFC in the text. The URLs it drops are
//     collected here, in document order, so the renderer can splice views back in.
//
//  Cross-platform on purpose: only Android renders through it, but it is built and
//  unit-tested on iOS against the same captured pages the parser suites use.
//

import Foundation
import SwiftSoup

/// FA markup restated for `AnnotatedString.fromHtml`, with what that parser discards.
public struct FANormalizedHTML: Hashable, Sendable {
    /// The rewritten markup. Every `<hr>` in it is a direct child of the root.
    public var html: String
    /// Every `<img>` of the document, in the order their U+FFFC placeholders appear.
    public var images: [FAInlineImage]
    /// The markup cut at its rules, which `fromHtml` renders as nothing at all. Each
    /// fragment is rendered on its own, with a divider drawn between consecutive ones.
    public var fragments: [Fragment]

    /// A run of markup between two rules, and the images its placeholders stand for.
    public struct Fragment: Hashable, Sendable {
        public var html: String
        public var images: [FAInlineImage]

        public init(html: String, images: [FAInlineImage]) {
            self.html = html
            self.images = images
        }
    }

    public init(html: String, images: [FAInlineImage], fragments: [Fragment]) {
        self.html = html
        self.images = images
        self.fragments = fragments
    }
}

public enum FAHTMLNormalizer {
    /// What the renderer actually needs: the markup already cut at its rules. The
    /// whole-document view below re-serialises the tree and walks it again for nothing.
    public static func fragments(of html: String) throws -> [FANormalizedHTML.Fragment] {
        try fragments(of: try normalizedRoot(html))
    }

    /// The whole normalised document. Only the tests read it — production goes through
    /// `fragments(of:)`.
    static func normalized(_ html: String) throws -> FANormalizedHTML {
        let root = try normalizedRoot(html)
        return FANormalizedHTML(
            html: try root.html(),
            images: try images(in: root),
            fragments: try fragments(of: root)
        )
    }

    private static func normalizedRoot(_ html: String) throws -> Element {
        let document = try SwiftSoup.parse(html)
        let root = document.body() ?? document
        try dropUnrenderableImages(in: root)
        try rewriteAlignment(in: root)
        try hoistRules(in: root)
        return root
    }

    // MARK: Fragments

    /// Cuts the document at its (now top-level) rules, so the renderer can draw its own
    /// divider between the pieces — `fromHtml` renders an `<hr>` as nothing whatsoever.
    private static func fragments(of root: Element) throws -> [FANormalizedHTML.Fragment] {
        var result: [FANormalizedHTML.Fragment] = []
        var nodes: [Node] = []

        func flush() throws {
            defer { nodes = [] }
            let html = try nodes.map { try $0.outerHtml() }.joined()
            // A rule at the very start or end, or two in a row, would otherwise leave an
            // empty fragment behind — and with it a doubled divider.
            guard !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let images = try nodes.compactMap { $0 as? Element }
                .flatMap { try $0.getElementsByTag("img").compactMap(image(from:)) }
            result.append(FANormalizedHTML.Fragment(html: html, images: images))
        }

        for node in root.getChildNodes() {
            if (node as? Element)?.tagName().lowercased() == "hr" {
                try flush()
            } else {
                nodes.append(node)
            }
        }
        try flush()
        return result
    }

    // MARK: Alignment

    /// Restates FA's alignment vocabulary as `text-align` on an element `fromHtml` treats
    /// as a block, which is the only form it reads it in.
    private static func rewriteAlignment(in root: Element) throws {
        for element in try root.getAllElements() {
            guard let alignment = try alignment(of: element) else { continue }
            let tag = element.tagName().lowercased()
            // `<code class="bbcode_center">` is the common case: unrecognised, so it has
            // to become a block tag. A tag that already is one keeps its own meaning —
            // renaming `<h4 class="bbcode_center">` would cost the heading.
            if !blockTags.contains(tag) {
                // Anything else is left as it stands: `fromHtml` would ignore alignment on
                // an inline element anyway, and making a block of a `<td>` or a `<span>`
                // destroys the table row or paragraph it sits in.
                guard renameableTags.contains(tag) else { continue }
                _ = try element.tagName("div")
            }
            try setTextAlign(alignment, on: element)
        }
    }

    /// The alignment an element states, by class, by `align` attribute or by style.
    private static func alignment(of element: Element) throws -> String? {
        // An element with no content of its own has nothing to align: FA writes
        // `<img align="middle">`, where `align` is *vertical* alignment and reading it
        // as text alignment would turn the image into a block and lose it.
        guard !voidTags.contains(element.tagName().lowercased()) else { return nil }

        let classes = element.faClassNames
        if !classes.isDisjoint(with: centerClasses) { return "center" }
        if !classes.isDisjoint(with: trailingClasses) { return "end" }
        if !classes.isDisjoint(with: leadingClasses) { return "start" }
        // `fromHtml` reads neither `align="…"` nor the physical `left`/`right` values, so
        // both are normalised to the logical ones it does read.
        for value in [try element.attr("align"), element.faStyle["text-align"] ?? ""] {
            switch value.trimmingCharacters(in: .whitespaces).lowercased() {
            case "center": return "center"
            case "right", "end": return "end"
            case "left", "start": return "start"
            default: continue
            }
        }
        return nil
    }

    private static func setTextAlign(_ alignment: String, on element: Element) throws {
        var declarations = element.faStyle
        declarations["text-align"] = alignment
        let style = declarations
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ";")
        _ = try element.attr("style", style)
    }

    // MARK: Rules

    /// Lifts every `<hr>` to a direct child of `root`, splitting the elements it sits
    /// inside so the markup on each side keeps the styling it had.
    ///
    /// FA nests its rules inside the wrapper that carries the description's alignment, so
    /// splitting the serialised HTML on `<hr>` without this would leave the second half
    /// with no opening tag — and no alignment.
    private static func hoistRules(in root: Element) throws {
        // `getElementsByTag` hands them back in document order, not deepest-first —
        // termination comes from each pass lifting one rule exactly one level.
        while let rule = try root.getElementsByTag("hr").first(where: { $0.parent() !== root }) {
            guard let parent = rule.parent() else { break }
            // A rule its parent doesn't list as a child would be re-selected forever.
            guard try split(parent, at: rule) else { break }
        }
    }

    /// Splits `element` around `rule`: what preceded the rule stays, what followed it
    /// moves into a copy, and the rule itself ends up between them one level up.
    ///
    /// - Returns: `false` when `rule` isn't among `element`'s children, so there was
    ///   nothing to split.
    @discardableResult
    private static func split(_ element: Element, at rule: Element) throws -> Bool {
        let children = element.getChildNodes()
        guard let position = children.firstIndex(where: { $0 === rule }) else { return false }

        let successor = try shallowCopy(of: element)
        for child in children[(position + 1)...] {
            try child.remove()
            _ = try successor.appendChild(child)
        }
        try rule.remove()

        _ = try element.after(rule)
        if !successor.getChildNodes().isEmpty {
            _ = try rule.after(successor)
        }
        // An element that held nothing but the rule would otherwise render as a gap.
        if element.getChildNodes().isEmpty {
            try element.remove()
        }
        return true
    }

    private static func shallowCopy(of element: Element) throws -> Element {
        let copy = Element(try Tag.valueOf(element.tagName()), element.getBaseUriUTF8())
        for attribute in element.getAttributes() ?? Attributes() {
            _ = try copy.attr(attribute.getKey(), attribute.getValue())
        }
        return copy
    }

    // MARK: Images

    /// Every `<img>` in document order — the order `fromHtml`'s U+FFFC placeholders
    /// appear in, since it emits exactly one per image and drops nothing else.
    private static func images(in root: Element) throws -> [FAInlineImage] {
        try root.getElementsByTag("img").compactMap(image(from:))
    }

    /// Drops every `<img>` there is nothing to splice in for. `android.text.Html` emits a
    /// U+FFFC per image whatever its `src` says, and the renderer pairs the i-th
    /// placeholder with the i-th image — so one unusable source would shift every later
    /// image in the fragment onto the wrong picture.
    private static func dropUnrenderableImages(in root: Element) throws {
        for element in try root.getElementsByTag("img") where try image(from: element) == nil {
            try element.remove()
        }
    }

    private static func image(from element: Element) throws -> FAInlineImage? {
        guard let url = try element.attr("src").faURL else { return nil }
        let alt = try element.attr("alt")
        return FAInlineImage(
            url: url,
            width: dimension(try element.attr("width")),
            height: dimension(try element.attr("height")),
            alt: alt.isEmpty ? nil : alt,
            // FA marks an inline avatar on the *link*, never on the image itself.
            isAvatar: element.faClassNames.contains("iconusername")
                || element.parents().contains { $0.faClassNames.contains("iconusername") }
        )
    }

    /// The pixel size a dimension attribute states, if it states one at all.
    /// `"300"` and `"300px"` are 300; `"100%"`, `""` and `"0"` are no size.
    private static func dimension(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespaces).lowercased()
        let number = trimmed.hasSuffix("px") ? String(trimmed.dropLast(2)) : trimmed
        guard let size = Double(number), size > 0 else { return nil }
        return size
    }

    // MARK: Vocabulary

    /// The tags `android.text.Html` lays out as blocks, and so reads `text-align` on.
    private static let blockTags: Set<String> = [
        "div", "p", "blockquote", "li", "ul", "ol",
        "h1", "h2", "h3", "h4", "h5", "h6",
    ]
    /// The only tags worth turning into a block: FA's `[center]` carrier and the element
    /// that means nothing but alignment in the first place.
    private static let renameableTags: Set<String> = ["code", "center"]
    /// Elements that hold no content, so nothing about them is text alignment.
    private static let voidTags: Set<String> = [
        "img", "br", "hr", "input", "area", "col", "embed", "source", "track", "wbr",
    ]
    private static let centerClasses: Set<String> = ["bbcode_center", "aligncenter"]
    private static let leadingClasses: Set<String> = ["bbcode_left", "alignleft"]
    private static let trailingClasses: Set<String> = ["bbcode_right", "alignright"]
}

extension String {
    /// Absolute URL for an `href`/`src`, resolving FA's site-relative links.
    var faURL: URL? {
        if hasPrefix("//") { return URL(string: "https:" + self) }
        if hasPrefix("/") { return URL(string: "https://www.furaffinity.net" + self) }
        // A path-relative `src` parses fine but can never be loaded: the document's real
        // base isn't known here, so there is nothing to resolve it against.
        guard let url = URL(string: self), url.scheme != nil else { return nil }
        return url
    }
}

private extension Element {
    var faClassNames: Set<String> {
        guard let value = try? attr("class"), !value.isEmpty else { return [] }
        return Set(value.split(whereSeparator: \.isWhitespace).map(String.init))
    }

    /// The element's `style` attribute as declarations, keyed by lowercased property.
    /// Values are kept verbatim — `setTextAlign` writes the whole attribute back, and a
    /// lowercased `url(…/AbC.png)` is a 404 on the CDN.
    var faStyle: [String: String] {
        guard let style = try? attr("style"), !style.isEmpty else { return [:] }
        return style.split(separator: ";").reduce(into: [:]) { result, declaration in
            let parts = declaration.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return }
            result[parts[0].trimmingCharacters(in: .whitespaces).lowercased()] =
                parts[1].trimmingCharacters(in: .whitespaces)
        }
    }
}
