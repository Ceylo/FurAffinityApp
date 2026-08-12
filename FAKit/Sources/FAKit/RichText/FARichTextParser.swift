//
//  FARichTextParser.swift
//  FAKit
//
//  A SwiftSoup walk over FA's rich text, emitting the `FAAttributes` vocabulary.
//
//  Scope is deliberately FA's own markup, not HTML at large: the tags and `bbcode_*`
//  classes the site's BBCode compiler emits, styled by `Resources/ui_theme_dark.css`
//  (which is exactly what the Apple build renders through). Anything outside that set
//  degrades to plain text rather than being dropped.
//

import Foundation
import SwiftSoup

public enum FARichTextParser {
    /// Parses an FA HTML document (or fragment) into styled, block-tagged text.
    public static func attributedString(fromFAHTML html: String) throws -> AttributedString {
        let document = try SwiftSoup.parse(html)
        var builder = Builder()
        builder.walk(node: document.body() ?? document, context: .init())
        return builder.finish()
    }
}

// MARK: - Walk context

/// Everything a node inherits from its ancestors.
private struct Context {
    var inline = FAInlineStyle()
    var link: URL?
    var kind: FABlock.Kind = .paragraph
    var alignment: FABlock.Alignment = .leading
    /// Nesting depth of `ul`/`ol`, 0 outside any list.
    var listDepth = 0
    /// Position of this `<li>` in its ordered list; nil in a bulleted one.
    var ordinal: Int?
    /// Set on the children of an `<a class="iconusername">`, which is where FA puts the
    /// marker for an inline avatar — never on the `<img>` itself.
    var isInsideAvatarLink = false
}

// MARK: - Builder

private struct Builder {
    struct Run {
        var text: String
        var inline: FAInlineStyle
        var link: URL?
        var image: FAInlineImage?
    }

    private struct Block {
        var kind: FABlock.Kind
        var alignment: FABlock.Alignment
        var runs: [Run]
    }

    private var blocks: [Block] = []
    private var current: Block?
    /// HTML collapses runs of whitespace, and drops them entirely at a block/line start.
    private var atCollapsedBoundary = true

    // MARK: Text accumulation

    mutating func append(_ text: String, image: FAInlineImage? = nil, _ context: Context) {
        guard !text.isEmpty else { return }
        if current == nil {
            current = Block(kind: context.kind, alignment: context.alignment, runs: [])
        }
        current?.runs.append(Run(text: text, inline: context.inline,
                                link: context.link, image: image))
        atCollapsedBoundary = text.hasSuffix(" ") || text.hasSuffix("\n")
    }

    /// Appends a text node, applying HTML whitespace collapsing.
    mutating func appendText(_ raw: String, _ context: Context) {
        var collapsed = raw.collapsingHTMLWhitespace
        if atCollapsedBoundary, collapsed.hasPrefix(" ") {
            collapsed.removeFirst()
        }
        append(collapsed, context)
    }

    /// A `<br>`. Any space it would strand at the end of the line goes with it — a
    /// browser wouldn't draw it, and in a centred block it would shift the whole line.
    mutating func appendLineBreak(_ context: Context) {
        if current != nil {
            Self.trim(&current!.runs, from: .trailing, characters: [" "])
        }
        append("\n", context)
    }

    /// Ends the current block. Empty blocks are dropped, so redundant `<div>`/`<p>`
    /// nesting doesn't produce phantom gaps.
    mutating func breakBlock() {
        defer { atCollapsedBoundary = true }
        guard var block = current else { return }
        current = nil
        // Line breaks that merely abut a block boundary aren't content: the renderer's
        // inter-block spacing is what separates blocks, so a leading/trailing `<br>`
        // would read as a stray empty line.
        Self.trim(&block.runs, from: .leading, characters: [" ", "\n"])
        Self.trim(&block.runs, from: .trailing, characters: [" ", "\n"])
        guard !block.runs.isEmpty else { return }
        blocks.append(block)
    }

    private enum Edge { case leading, trailing }

    private static func trim(_ runs: inout [Run], from edge: Edge,
                             characters: Set<Character>) {
        while !runs.isEmpty {
            let index = edge == .leading ? runs.startIndex : runs.index(before: runs.endIndex)
            var run = runs[index]
            // An image run is content, not whitespace — it stops the trim.
            guard run.image == nil else { return }
            while let character = edge == .leading ? run.text.first : run.text.last,
                  characters.contains(character) {
                if edge == .leading {
                    run.text.removeFirst()
                } else {
                    run.text.removeLast()
                }
            }
            if run.text.isEmpty {
                runs.remove(at: index)
            } else {
                runs[index] = run
                return
            }
        }
    }

    mutating func finish() -> AttributedString {
        breakBlock()
        var result = AttributedString()
        for (index, block) in blocks.enumerated() {
            let attributes = FABlock(kind: block.kind, alignment: block.alignment, index: index)
            for run in block.runs {
                var attributed = AttributedString(run.text)
                if run.inline != .default {
                    attributed.faInline = run.inline
                }
                if let link = run.link {
                    attributed.link = link
                }
                if let image = run.image {
                    attributed.faImage = image
                }
                attributed.faBlock = attributes
                result += attributed
            }
        }
        return result
    }

    // MARK: Walk

    mutating func walk(node: Node, context: Context) {
        if let textNode = node as? TextNode {
            appendText(textNode.getWholeText(), context)
            return
        }
        guard let element = node as? Element else { return }

        let classes = element.faClassNames
        let tag = element.tagName().lowercased()

        switch tag {
        case "br":
            appendLineBreak(context)
            return
        case "hr":
            breakBlock()
            var ruleContext = context
            ruleContext.kind = .rule
            ruleContext.inline = FAInlineStyle()
            append(Self.objectReplacement, ruleContext)
            breakBlock()
            return
        case "img":
            appendImage(element, classes: classes, context: context)
            return
        case "script", "style", "noscript":
            return
        default:
            break
        }

        var childContext = context
        applyInlineStyling(of: element, tag: tag, classes: classes, to: &childContext)
        if classes.contains("iconusername") { childContext.isInsideAvatarLink = true }

        let alignment = Self.alignment(for: element, classes: classes)
        if let alignment { childContext.alignment = alignment }

        if tag == "ul" || tag == "ol" {
            childContext.listDepth += 1
        }

        // A block boundary either because the element states one (heading, quote, list
        // item) or because its tag/alignment class is display:block in FA's stylesheet.
        let kind = Self.blockKind(for: tag, classes: classes, context: context)
        let opensBlock = kind != nil || Self.isBlockLevel(tag)
            || !classes.isDisjoint(with: Self.alignmentClasses)
        if opensBlock {
            breakBlock()
            childContext.kind = kind ?? .paragraph
        }

        var ordinal = 1
        for child in element.getChildNodes() {
            var perChild = childContext
            if tag == "ol", (child as? Element)?.tagName().lowercased() == "li" {
                perChild.ordinal = ordinal
                ordinal += 1
            }
            walk(node: child, context: perChild)
        }

        if opensBlock { breakBlock() }
    }

    // MARK: Element mapping

    private mutating func appendImage(_ element: Element, classes: Set<String>, context: Context) {
        guard let source = try? element.attr("src"), let url = source.faURL else { return }
        let alt = (try? element.attr("alt")).flatMap { $0.isEmpty ? nil : $0 }
        let image = FAInlineImage(
            url: url,
            width: (try? element.attr("width")).flatMap(Double.init),
            height: (try? element.attr("height")).flatMap(Double.init),
            alt: alt,
            isAvatar: classes.contains("iconusername") || context.isInsideAvatarLink
        )
        append(Self.objectReplacement, image: image, context)
    }

    private func applyInlineStyling(of element: Element, tag: String,
                                    classes: Set<String>, to context: inout Context) {
        switch tag {
        case "b", "strong":
            context.inline.bold = true
        case "i", "em":
            context.inline.italic = true
        case "u", "ins":
            context.inline.underline = true
        case "s", "strike", "del":
            context.inline.strikethrough = true
        case "sub":
            context.inline.baseline = .sub
            context.inline.sizeScale *= Self.smallerScale
        case "sup":
            context.inline.baseline = .super
            context.inline.sizeScale *= Self.smallerScale
        case "code", "tt", "kbd", "samp", "pre":
            // FA reuses `<code>` as the *block* container for [left]/[center]/[right],
            // whose CSS explicitly resets the family back to the body's sans-serif.
            if classes.isDisjoint(with: Self.alignmentClasses) {
                context.inline.monospace = true
            }
        case "a":
            if let href = try? element.attr("href"), let url = href.faURL {
                context.link = url
            }
        case "font":
            if let color = try? element.attr("color"), let argb = color.cssColorARGB {
                context.inline.colorARGB = argb
            }
        default:
            break
        }

        if classes.contains("bbcode_b") { context.inline.bold = true }
        if classes.contains("bbcode_i") { context.inline.italic = true }
        if classes.contains("bbcode_u") { context.inline.underline = true }
        if classes.contains("bbcode_s") { context.inline.strikethrough = true }
        if classes.contains("bbcode_quote_name") { context.inline.bold = true }
        if classes.contains("bbcode_quote") { context.inline.italic = true }

        for (name, value) in element.faInlineStyle {
            switch name {
            case "color":
                if let argb = value.cssColorARGB { context.inline.colorARGB = argb }
            case "font-size":
                if let scale = value.cssFontSizeScale { context.inline.sizeScale = scale }
            case "font-weight":
                if value == "bold" || (Int(value).map { $0 >= 600 } ?? false) {
                    context.inline.bold = true
                }
            case "font-style":
                if value == "italic" || value == "oblique" { context.inline.italic = true }
            case "text-decoration", "text-decoration-line":
                if value.contains("underline") { context.inline.underline = true }
                if value.contains("line-through") { context.inline.strikethrough = true }
            default:
                break
            }
        }
    }

    private static func blockKind(for tag: String, classes: Set<String>,
                                  context: Context) -> FABlock.Kind? {
        if let level = headingLevel(tag: tag, classes: classes) {
            return .heading(level: level)
        }
        if classes.contains("bbcode_quote") || tag == "blockquote" {
            return .quote
        }
        if tag == "li" {
            return .listItem(depth: max(context.listDepth, 1), ordinal: context.ordinal)
        }
        return nil
    }

    private static func headingLevel(tag: String, classes: Set<String>) -> Int? {
        for level in 1...5 where classes.contains("bbcode_h\(level)") {
            return level
        }
        guard tag.count == 2, tag.hasPrefix("h"), let level = Int(tag.dropFirst()),
              (1...6).contains(level) else { return nil }
        return min(level, 5)
    }

    private static func alignment(for element: Element,
                                  classes: Set<String>) -> FABlock.Alignment? {
        if classes.contains("bbcode_center") || classes.contains("aligncenter") { return .center }
        if classes.contains("bbcode_right") || classes.contains("alignright") { return .trailing }
        if classes.contains("bbcode_left") || classes.contains("alignleft") { return .leading }
        switch element.faInlineStyle.first(where: { $0.name == "text-align" })?.value {
        case "center": return .center
        case "right": return .trailing
        case "left": return .leading
        default: return nil
        }
    }

    private static func isBlockLevel(_ tag: String) -> Bool {
        blockLevelTags.contains(tag)
    }

    private static let blockLevelTags: Set<String> = [
        "p", "div", "section", "article", "header", "footer", "ul", "ol", "table", "tr",
    ]
    private static let alignmentClasses: Set<String> = [
        "bbcode_left", "bbcode_center", "bbcode_right",
    ]
    /// CSS `font-size: smaller`, which is what `<sub>`/`<sup>` get by default.
    private static let smallerScale = 0.83
    private static let objectReplacement = "\u{FFFC}"
}

// MARK: - Element/String helpers

private extension Element {
    var faClassNames: Set<String> {
        guard let value = try? attr("class"), !value.isEmpty else { return [] }
        return Set(value.split(whereSeparator: \.isWhitespace).map(String.init))
    }

    /// The element's `style` attribute as lowercased `name`/`value` pairs.
    var faInlineStyle: [(name: String, value: String)] {
        guard let style = try? attr("style"), !style.isEmpty else { return [] }
        return style.split(separator: ";").compactMap { declaration in
            let parts = declaration.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }
            return (parts[0].trimmingCharacters(in: .whitespaces).lowercased(),
                    parts[1].trimmingCharacters(in: .whitespaces).lowercased())
        }
    }
}

extension String {
    /// Absolute URL for an `href`/`src`, resolving FA's site-relative links.
    var faURL: URL? {
        if hasPrefix("//") { return URL(string: "https:" + self) }
        if hasPrefix("/") { return URL(string: "https://www.furaffinity.net" + self) }
        return URL(string: self)
    }

    /// Runs of HTML whitespace folded into a single space, as a browser would.
    var collapsingHTMLWhitespace: String {
        var result = ""
        var inWhitespace = false
        for character in self {
            if character == " " || character == "\t" || character == "\n"
                || character == "\r" || character == "\u{0C}" {
                inWhitespace = true
            } else {
                if inWhitespace { result.append(" ") }
                inWhitespace = false
                result.append(character)
            }
        }
        if inWhitespace { result.append(" ") }
        return result
    }

    /// `#rgb`, `#rrggbb`, `#aarrggbb` or `rgb()`/`rgba()` as `0xAARRGGBB`.
    var cssColorARGB: UInt32? {
        let value = trimmingCharacters(in: .whitespaces).lowercased()
        if value.hasPrefix("#") {
            let digits = String(value.dropFirst())
            switch digits.count {
            case 3:
                guard let short = UInt32(digits, radix: 16) else { return nil }
                let red = (short >> 8) & 0xF, green = (short >> 4) & 0xF, blue = short & 0xF
                return 0xFF00_0000 | (red * 0x11) << 16 | (green * 0x11) << 8 | (blue * 0x11)
            case 6:
                guard let rgb = UInt32(digits, radix: 16) else { return nil }
                return 0xFF00_0000 | rgb
            case 8:
                return UInt32(digits, radix: 16)
            default:
                return nil
            }
        }
        guard value.hasPrefix("rgb"), let open = value.firstIndex(of: "("),
              let close = value.firstIndex(of: ")") else { return nil }
        let components = value[value.index(after: open)..<close]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard components.count >= 3,
              let red = UInt32(components[0]), let green = UInt32(components[1]),
              let blue = UInt32(components[2]) else { return nil }
        let alpha = components.count > 3
            ? UInt32((Double(components[3]) ?? 1).clamped(to: 0...1) * 255)
            : 255
        return alpha << 24 | (red & 0xFF) << 16 | (green & 0xFF) << 8 | (blue & 0xFF)
    }

    /// A CSS `font-size` as a multiple of FA's 16px body text.
    var cssFontSizeScale: Double? {
        let value = trimmingCharacters(in: .whitespaces).lowercased()
        if value.hasSuffix("px"), let points = Double(value.dropLast(2)) {
            return points / 16
        }
        if value.hasSuffix("pt"), let points = Double(value.dropLast(2)) {
            return points * 4 / 3 / 16
        }
        if value.hasSuffix("em"), let scale = Double(value.dropLast(2)) {
            return scale
        }
        if value.hasSuffix("%"), let percent = Double(value.dropLast()) {
            return percent / 100
        }
        return nil
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
