//
//  FACSSResolver.swift
//  FAKit
//
//  Applies FA's theme stylesheet to a document as markup `AnnotatedString.fromHtml`
//  reads. That parser knows nothing of `<style>` or classes: it reads `color`,
//  `background(-color)` and `text-decoration` from a `<span>`'s `style`, and weight and
//  slant only from tags. So the cascade is resolved here, per element, and each result
//  is restated as a `<span style>` and `<b>`/`<i>` around the element's children.
//
//  Only what that vocabulary can carry is kept. `font-size` is left out on purpose:
//  `fromHtml` already sizes `h1`–`h6`. Spoilers are left visible: their rule paints the
//  text the colour of its background until hovered, which nothing here can undo.
//
//  Cross-platform on purpose, like `FAHTMLNormalizer`: only Android renders through it,
//  but it is unit-tested on both.
//

import Foundation
import SwiftSoup

/// FA's theme stylesheet, parsed once into what rich text can use of it.
public struct FAStylesheet: Sendable {
    let resolver: FACSSResolver

    public init(css: String) {
        resolver = FACSSResolver(stylesheet: css)
    }

    /// The current theme's stylesheet: today's download, or the bundled copy.
    @MainActor
    public static var current: FAStylesheet {
        get async { await CSSInliner.shared.parsedStylesheet(for: .current) }
    }
}

struct FACSSResolver: Sendable {
    /// One selector of a rule, with the declarations it carries that `fromHtml` can read.
    struct Rule: Sendable {
        var selector: String
        var specificity: Int
        var order: Int
        var declarations: [Property: Declaration]
        /// The classes and tag its subject must have, to skip selectors that can't match
        /// before asking SwiftSoup.
        var subjectClasses: [String]
        var subjectTag: String?
    }

    struct Declaration: Sendable, Equatable {
        var value: String
        var important: Bool
    }

    enum Property: String, Sendable, CaseIterable {
        case color
        case backgroundColor = "background-color"
        case textDecoration = "text-decoration"
        case fontWeight = "font-weight"
        case fontStyle = "font-style"
    }

    let rules: [Rule]

    init(stylesheet: String) {
        var rules: [Rule] = []
        for (prelude, body) in Self.topLevelRules(in: stylesheet) {
            let declarations = Self.translatableDeclarations(in: body)
            guard !declarations.isEmpty else { continue }
            for selector in Self.selectors(in: prelude) where Self.isSupported(selector) {
                let subject = Self.subject(of: selector)
                rules.append(Rule(
                    selector: selector,
                    specificity: Self.specificity(of: selector),
                    order: rules.count,
                    declarations: declarations,
                    subjectClasses: subject.classes,
                    subjectTag: subject.tag
                ))
            }
        }
        self.rules = rules
    }

    // MARK: Applying

    /// Resolves the cascade over `root`'s descendants and writes it into the markup.
    /// `root` itself is left alone: it stands for the page body, whose colours are the
    /// app's to choose.
    func apply(to root: Element) throws {
        let elements = try root.getAllElements().array().filter { $0 !== root }
        guard !elements.isEmpty else { return }
        var classes = Set<String>()
        var tags = Set<String>()
        for element in elements {
            tags.insert(element.tagName().lowercased())
            classes.formUnion(element.faClassNames)
        }

        typealias Winner = (declaration: Declaration, specificity: Int, order: Int)
        var resolved: [ObjectIdentifier: (element: Element, winners: [Property: Winner])] = [:]
        for rule in rules {
            if let tag = rule.subjectTag, !tags.contains(tag) { continue }
            guard rule.subjectClasses.allSatisfy(classes.contains) else { continue }
            // SwiftSoup's selector grammar is narrower than CSS's; whatever it can't
            // parse can't be applied either.
            guard let matches = try? root.select(rule.selector) else { continue }
            for element in matches where element !== root {
                var entry = resolved[ObjectIdentifier(element)] ?? (element, [:])
                for (property, declaration) in rule.declarations {
                    if let current = entry.winners[property],
                       Self.precedes(current, (declaration, rule.specificity, rule.order)) {
                        continue
                    }
                    entry.winners[property] = (declaration, rule.specificity, rule.order)
                }
                resolved[ObjectIdentifier(element)] = entry
            }
        }

        for (element, winners) in resolved.values {
            // The element's own `style` beats every rule but an `!important` one, and
            // `fromHtml` already reads it where it can.
            let inline = Self.translatableDeclarations(in: (try? element.attr("style")) ?? "")
            let values = winners
                .filter { property, winner in winner.declaration.important || inline[property] == nil }
                .mapValues(\.declaration.value)
            try restate(values, on: element)
        }
    }

    /// Whether `a` beats `b`: `!important` first, then specificity, then source order.
    private static func precedes(
        _ a: (declaration: Declaration, specificity: Int, order: Int),
        _ b: (declaration: Declaration, specificity: Int, order: Int)
    ) -> Bool {
        if a.declaration.important != b.declaration.important { return a.declaration.important }
        if a.specificity != b.specificity { return a.specificity > b.specificity }
        return a.order > b.order
    }

    /// Wraps the element's children in what `fromHtml` reads: `<b>`, `<i>`, then a
    /// `<span style>`, outermost first.
    private func restate(_ values: [Property: String], on element: Element) throws {
        let tag = element.tagName().lowercased()
        guard !Self.voidTags.contains(tag), !element.getChildNodes().isEmpty else { return }

        var style: [String] = []
        // Links keep the app's tint, as `UITextView` gives them on iOS.
        if tag != "a", let color = values[.color] { style.append("color:\(color)") }
        if let background = values[.backgroundColor] { style.append("background-color:\(background)") }
        if let decoration = values[.textDecoration], decoration != "none" {
            style.append("text-decoration:\(decoration)")
        }

        var wrappers: [Element] = []
        if values[.fontWeight] == "bold", tag != "b", tag != "strong" {
            wrappers.append(Element(try Tag.valueOf("b"), element.getBaseUriUTF8()))
        }
        if values[.fontStyle] == "italic", tag != "i", tag != "em" {
            wrappers.append(Element(try Tag.valueOf("i"), element.getBaseUriUTF8()))
        }
        if !style.isEmpty {
            let span = Element(try Tag.valueOf("span"), element.getBaseUriUTF8())
            _ = try span.attr("style", style.joined(separator: ";"))
            wrappers.append(span)
        }
        guard let innermost = wrappers.last else { return }

        for child in element.getChildNodes() {
            try child.remove()
            _ = try innermost.appendChild(child)
        }
        for (outer, inner) in zip(wrappers, wrappers.dropFirst()) {
            _ = try outer.appendChild(inner)
        }
        _ = try element.appendChild(wrappers[0])
    }

    // MARK: Parsing

    /// Every top-level `prelude { body }`, comments stripped and at-rule blocks
    /// (`@media`, `@font-face`, `@keyframes`…) skipped whole.
    static func topLevelRules(in stylesheet: String) -> [(prelude: String, body: String)] {
        let css = stylesheet.replacing(/\/\*.*?\*\//.dotMatchesNewlines(), with: "")
        var rules: [(String, String)] = []
        var prelude = ""
        var body = ""
        var depth = 0
        var skipping = false

        for character in css {
            switch character {
            case "{":
                depth += 1
                if depth == 1 {
                    skipping = prelude.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@")
                } else if !skipping {
                    body.append(character)
                }
            case "}":
                depth = max(0, depth - 1)
                if depth == 0 {
                    if !skipping {
                        rules.append((prelude.trimmingCharacters(in: .whitespacesAndNewlines), body))
                    }
                    prelude = ""
                    body = ""
                    skipping = false
                } else if !skipping {
                    body.append(character)
                }
            case ";" where depth == 0:
                // A body-less at-rule, `@import …;` or `@charset …;`.
                prelude = ""
            default:
                if depth == 0 {
                    prelude.append(character)
                } else if !skipping {
                    body.append(character)
                }
            }
        }
        return rules
    }

    /// The comma-separated selectors of a prelude, split only at top level.
    static func selectors(in prelude: String) -> [String] {
        var selectors: [String] = []
        var current = ""
        var depth = 0
        for character in prelude {
            switch character {
            case "(", "[": depth += 1
            case ")", "]": depth = max(0, depth - 1)
            case "," where depth == 0:
                selectors.append(current)
                current = ""
                continue
            default: break
            }
            current.append(character)
        }
        selectors.append(current)
        return selectors
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
    }

    /// Whether a selector can describe rich text at all: no state (`:hover`), no
    /// generated content (`::before`), no page chrome (`#id`, `body`, `html`), and not
    /// the spoiler, which is kept visible.
    static func isSupported(_ selector: String) -> Bool {
        guard !selector.contains(":"), !selector.contains("#"),
              !selector.contains("bbcode_spoiler") else { return false }
        let types = selector
            .split(whereSeparator: { " >+~".contains($0) })
            .map { $0.prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" }).lowercased() }
        return !types.contains("body") && !types.contains("html")
    }

    /// (classes and attributes) × 100 + types; ids are never supported, so they don't count.
    static func specificity(of selector: String) -> Int {
        let compounds = selector.split(whereSeparator: { " >+~".contains($0) })
        var classes = 0
        var types = 0
        for compound in compounds {
            classes += compound.filter { $0 == "." || $0 == "[" }.count
            if compound.first?.isLetter == true { types += 1 }
        }
        return classes * 100 + types
    }

    /// The classes and tag the rightmost compound selector requires.
    private static func subject(of selector: String) -> (classes: [String], tag: String?) {
        guard let compound = selector.split(whereSeparator: { " >+~".contains($0) }).last
        else { return ([], nil) }
        // `a.b[c=d]` → tag `a`, classes `b`; the attribute part is left to SwiftSoup.
        let base = compound.prefix(while: { $0 != "[" })
        let parts = base.split(separator: ".", omittingEmptySubsequences: false)
        let tag = parts.first.map { $0.lowercased() }.flatMap { $0.isEmpty || $0 == "*" ? nil : $0 }
        return (parts.dropFirst().map(String.init).filter { !$0.isEmpty }, tag)
    }

    /// The declarations of a block that `fromHtml` can carry, normalised to what
    /// `restate` writes: a plain colour, an underline or strike, `bold`, `italic`.
    static func translatableDeclarations(in block: String) -> [Property: Declaration] {
        var result: [Property: Declaration] = [:]
        for raw in block.faTopLevelDeclarations {
            let parts = raw.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            let important = value.lowercased().hasSuffix("!important")
            if important {
                value = String(value.dropLast("!important".count))
                    .trimmingCharacters(in: .whitespaces)
            }

            let translated: (Property, String)?
            switch name {
            case "color":
                translated = plainColor(value).map { (.color, $0) }
            case "background-color", "background":
                translated = plainColor(value).map { (.backgroundColor, $0) }
            case "text-decoration", "text-decoration-line":
                let lowered = value.lowercased()
                translated = lowered.contains("underline") ? (.textDecoration, "underline")
                    : lowered.contains("line-through") ? (.textDecoration, "line-through")
                    : lowered.hasPrefix("none") ? (.textDecoration, "none")
                    : nil
            case "font-weight":
                let lowered = value.lowercased()
                if lowered == "bold" || lowered == "bolder" || (Int(lowered) ?? 0) >= 600 {
                    translated = (.fontWeight, "bold")
                } else if lowered == "normal" || lowered == "lighter" || Int(lowered) != nil {
                    translated = (.fontWeight, "normal")
                } else {
                    translated = nil
                }
            case "font-style":
                let lowered = value.lowercased()
                translated = (lowered == "italic" || lowered == "oblique") ? (.fontStyle, "italic")
                    : lowered == "normal" ? (.fontStyle, "normal")
                    : nil
            default:
                translated = nil
            }

            guard let (property, normalised) = translated else { continue }
            // Later wins within a block, unless the earlier one was `!important`.
            if let existing = result[property], existing.important, !important { continue }
            result[property] = Declaration(value: normalised, important: important)
        }
        return result
    }

    /// A colour `android.text.Html` can parse: `#rrggbb` (a `#rgb` is expanded) or a
    /// name. Keywords that mean "no colour of its own" and functional notations it
    /// doesn't read are dropped.
    static func plainColor(_ value: String) -> String? {
        let lowered = value.lowercased()
        if lowered.hasPrefix("#") {
            let hex = lowered.dropFirst()
            guard hex.allSatisfy(\.isHexDigit) else { return nil }
            switch hex.count {
            case 3: return "#" + hex.map { "\($0)\($0)" }.joined()
            case 6: return lowered
            default: return nil
            }
        }
        guard !lowered.isEmpty, lowered.allSatisfy({ $0.isLetter }),
              !["transparent", "inherit", "initial", "unset", "none", "currentcolor", "revert"]
                .contains(lowered) else { return nil }
        return lowered
    }

    private static let voidTags: Set<String> = [
        "img", "br", "hr", "input", "area", "col", "embed", "source", "track", "wbr",
    ]
}
