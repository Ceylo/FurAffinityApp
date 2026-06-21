//
//  StoryDocument.swift
//  FAKit
//
//  Created by Ceylo on 21/06/2026.
//

import Foundation
import UIKit
import PDFKit
import ZIPFoundation

/// Extracts readable rich text from a downloaded story-submission document so it
/// can be rendered as native, reflowing text while keeping bold/italic, relative
/// font sizes and paragraph structure. Returns `nil` for formats we can't read
/// (the caller should fall back to a document preview).
///
/// Runs carry only fonts (size + traits), never a foreground color, so the reader
/// can apply `.label` and stay correct in light/dark mode. Sizes are expressed
/// relative to ``bodyPointSize`` so the reader can normalize them to the user's
/// Dynamic Type body size.
public enum StoryDocument {
    /// Reference body size; heading/emphasis runs use multiples of this. The
    /// reader normalizes against the document's dominant size, so the absolute
    /// value only matters as a common baseline across formats.
    static let bodyPointSize: CGFloat = 17

    public static func richText(from data: Data, filename: String) -> AttributedString? {
        let ns: NSAttributedString?
        switch (filename as NSString).pathExtension.lowercased() {
        case "txt", "text", "md":
            ns = String(data: data, encoding: .utf8).map(plainAttributed)
        case "rtf":
            ns = rtfText(from: data)
        case "pdf":
            ns = pdfText(from: data)
        case "docx":
            ns = docxText(from: data)
        default:
            ns = nil
        }
        return ns.map { AttributedString($0) }
    }

    static func font(size: CGFloat, bold: Bool, italic: Bool) -> UIFont {
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let base = UIFont.systemFont(ofSize: size)
        guard !traits.isEmpty,
              let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    private static func plainAttributed(_ string: String) -> NSAttributedString {
        NSAttributedString(
            string: string,
            attributes: [.font: font(size: bodyPointSize, bold: false, italic: false)]
        )
    }

    private static func rtfText(from data: Data) -> NSAttributedString? {
        guard let attributed = try? NSMutableAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) else { return nil }

        // Drop baked-in colors so the reader's `.label` keeps dark mode readable.
        attributed.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: attributed.length))
        return attributed.length > 0 ? attributed : nil
    }

    private static func pdfText(from data: Data) -> NSAttributedString? {
        guard let document = PDFDocument(data: data) else { return nil }

        let result = NSMutableAttributedString()
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            appendReflowed(page: page, to: result)
        }

        result.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: result.length))
        let trimmedResult = trimmed(result)
        return trimmedResult.length > 0 ? trimmedResult : nil
    }

    /// A visual line of a PDF page: a contiguous run of characters sharing a row,
    /// with its on-page geometry (PDF space, origin bottom-left, y up).
    private struct PDFLine {
        var range: NSRange
        var minX: CGFloat
        var maxX: CGFloat
        var minY: CGFloat
        var maxY: CGFloat
        /// Horizontal extent of the line's leading word, used by the line-fill test.
        var firstWordMinX: CGFloat
        var firstWordMaxX: CGFloat
        var height: CGFloat { maxY - minY }
        var firstWordWidth: CGFloat { firstWordMaxX - firstWordMinX }
    }

    /// How two consecutive visual lines are joined when reflowing a PDF page.
    private enum LineJoin {
        /// Same paragraph, wrapped by width — join with a space (de-hyphenating).
        case softWrap
        /// A break inside a stacked block (e.g. the title lines) — a line break that
        /// stays in the same paragraph, so it gets no paragraph spacing.
        case lineBreak
        /// A new paragraph — gets the reader's paragraph spacing.
        case paragraph
    }

    /// Reconstructs paragraphs from a PDF page: PDFKit already breaks the text into
    /// visual lines (a `\n` per line, which is what shows orphaned words on screen).
    /// A break is a *soft wrap* (rejoined with a space) when the previous line was
    /// full — the next line's leading word wouldn't have fit (line-fill test);
    /// otherwise the line ended early on purpose and we keep the break. The leading
    /// short lines of the page (the title block) are kept as tight *line breaks*
    /// within one paragraph; every other kept break starts a new *paragraph*. This
    /// separates the title from the body and detects paragraph ends regardless of
    /// vertical spacing. Original per-character fonts (size + traits) are preserved.
    private static func appendReflowed(page: PDFPage, to result: NSMutableAttributedString) {
        let attributed = page.attributedString ?? NSAttributedString()
        let string = attributed.string as NSString
        let count = min(string.length, page.numberOfCharacters)
        guard count > 0 else { return }

        // Split into visual lines on newlines; gather per-line geometry.
        var lines: [PDFLine] = []
        var lineStart = 0
        func flushLine(end: Int) {
            let length = end - lineStart
            if length > 0 {
                var minX = CGFloat.greatestFiniteMagnitude, maxX = -CGFloat.greatestFiniteMagnitude
                var minY = CGFloat.greatestFiniteMagnitude, maxY = -CGFloat.greatestFiniteMagnitude
                var firstWordMinX = CGFloat.greatestFiniteMagnitude, firstWordMaxX = -CGFloat.greatestFiniteMagnitude
                var firstWordStarted = false, firstWordEnded = false
                var hasBounds = false
                for i in lineStart..<end {
                    let isSpace = Unicode.Scalar(string.character(at: i))
                        .map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false
                    let bounds = page.characterBounds(at: i)
                    let valid = bounds.width > 0 && bounds.height > 0
                    if valid {
                        hasBounds = true
                        minX = min(minX, bounds.minX); maxX = max(maxX, bounds.maxX)
                        minY = min(minY, bounds.minY); maxY = max(maxY, bounds.maxY)
                    }
                    if !firstWordEnded {
                        if isSpace {
                            if firstWordStarted { firstWordEnded = true }
                        } else if valid {
                            firstWordStarted = true
                            firstWordMinX = min(firstWordMinX, bounds.minX)
                            firstWordMaxX = max(firstWordMaxX, bounds.maxX)
                        }
                    }
                }
                if hasBounds {
                    if !firstWordStarted { firstWordMinX = minX; firstWordMaxX = maxX }
                    lines.append(PDFLine(range: NSRange(location: lineStart, length: length),
                                         minX: minX, maxX: maxX, minY: minY, maxY: maxY,
                                         firstWordMinX: firstWordMinX, firstWordMaxX: firstWordMaxX))
                }
            }
            lineStart = end + 1
        }
        for i in 0..<count where Unicode.Scalar(string.character(at: i)) == "\n" {
            flushLine(end: i)
        }
        flushLine(end: count)
        guard !lines.isEmpty else { return }

        let medianHeight = median(lines.map(\.height)) ?? bodyPointSize
        let bodyLeft = lines.map(\.minX).min() ?? 0
        let bodyRight = lines.map(\.maxX).max() ?? 0
        let spaceWidth = medianHeight * 0.25

        // The title block: the leading run of short lines that don't reach the body's
        // right margin. Breaks inside it stay tight; the break into the body and all
        // body breaks become paragraphs.
        let titleMaxX = bodyLeft + (bodyRight - bodyLeft) * 0.6
        var titleEnd = 0
        while titleEnd < lines.count, lines[titleEnd].maxX < titleMaxX { titleEnd += 1 }

        for (index, line) in lines.enumerated() {
            let substring = attributed.attributedSubstring(from: line.range)

            if index == 0 {
                // First line of a later page continues as a new paragraph.
                appendSeparated(substring, to: result, join: result.length > 0 ? .paragraph : .softWrap)
                continue
            }

            // Within the title block, keep tight line breaks.
            if index < titleEnd {
                appendSeparated(substring, to: result, join: .lineBreak)
                continue
            }

            // Line-fill test: if the previous line had room for this line's first
            // word (plus a space), it ended early on purpose → new paragraph;
            // otherwise it was full → soft wrap we rejoin.
            let previous = lines[index - 1]
            let available = bodyRight - previous.maxX
            let nextWordWouldFit = available >= spaceWidth + line.firstWordWidth
            appendSeparated(substring, to: result, join: nextWordWouldFit ? .paragraph : .softWrap)
        }
    }

    /// Appends `substring` to `result`, separating it from the existing text per
    /// `join`: a paragraph break (`\n`), a tight line break (`\u{2028}`, same
    /// paragraph), or a soft-wrap space — joining hyphenated words without the hyphen.
    private static func appendSeparated(_ substring: NSAttributedString, to result: NSMutableAttributedString, join: LineJoin) {
        if result.length == 0 {
            result.append(substring)
            return
        }
        switch join {
        case .paragraph:
            result.append(NSAttributedString(string: "\n"))
            result.append(substring)
            return
        case .lineBreak:
            result.append(NSAttributedString(string: "\u{2028}"))
            result.append(substring)
            return
        case .softWrap:
            break
        }
        let existing = result.string as NSString
        let lastChar = existing.character(at: existing.length - 1)
        if Unicode.Scalar(lastChar) == "-", existing.length >= 2,
           CharacterSet.letters.contains(Unicode.Scalar(existing.character(at: existing.length - 2))!) {
            result.deleteCharacters(in: NSRange(location: existing.length - 1, length: 1))
            result.append(substring)
        } else {
            result.append(NSAttributedString(string: " ", attributes: [.font: font(size: bodyPointSize, bold: false, italic: false)]))
            result.append(substring)
        }
    }

    private static func median(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    private static func docxText(from data: Data) -> NSAttributedString? {
        guard let archive = try? Archive(data: data, accessMode: .read, pathEncoding: nil),
              let entry = archive["word/document.xml"] else {
            return nil
        }

        var xml = Data()
        guard (try? archive.extract(entry) { xml.append($0) }) != nil else {
            return nil
        }

        let parser = XMLParser(data: xml)
        let delegate = DocxTextParser()
        parser.delegate = delegate
        guard parser.parse() else { return nil }

        let result = trimmed(delegate.result)
        return result.length > 0 ? result : nil
    }

    /// Trims leading/trailing whitespace and newlines, preserving run attributes.
    private static func trimmed(_ attributed: NSAttributedString) -> NSAttributedString {
        let string = attributed.string as NSString
        let whitespace = CharacterSet.whitespacesAndNewlines
        var start = 0
        var end = string.length
        while start < end, let scalar = Unicode.Scalar(string.character(at: start)), whitespace.contains(scalar) {
            start += 1
        }
        while end > start, let scalar = Unicode.Scalar(string.character(at: end - 1)), whitespace.contains(scalar) {
            end -= 1
        }
        return attributed.attributedSubstring(from: NSRange(location: start, length: end - start))
    }
}

/// Builds an attributed string from a Word `document.xml`: text inside `<w:t>`,
/// run traits from `<w:b>` / `<w:i>` / `<w:sz>`, paragraph breaks on `</w:p>`,
/// line breaks on `<w:br>`, tabs on `<w:tab>`. Paragraphs are separated by a
/// single newline; the reader supplies paragraph spacing.
private final class DocxTextParser: NSObject, XMLParserDelegate {
    private(set) var result = NSMutableAttributedString()

    /// Typical Word default body size (half-points are halved into points).
    private let defaultSize: CGFloat = 12

    private var stack: [String] = []
    private var inText = false

    // Current run state, applied when the run's text is emitted.
    private var bold = false
    private var italic = false
    private var size: CGFloat = 12

    private var insideRun: Bool { stack.contains("w:r") }

    private func boolValue(_ attributes: [String: String]) -> Bool {
        switch attributes["w:val"]?.lowercased() {
        case "0", "false", "off": return false
        default: return true
        }
    }

    private func append(_ string: String) {
        let font = StoryDocument.font(size: size, bold: bold, italic: italic)
        result.append(NSAttributedString(string: string, attributes: [.font: font]))
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        stack.append(elementName)
        switch elementName {
        case "w:t": inText = true
        case "w:tab" where insideRun: append("\t")
        case "w:br", "w:cr": if insideRun { append("\n") }
        case "w:b" where insideRun: bold = boolValue(attributes)
        case "w:i" where insideRun: italic = boolValue(attributes)
        case "w:sz" where insideRun:
            if let raw = attributes["w:val"], let halfPoints = Double(raw) {
                size = CGFloat(halfPoints) / 2
            }
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inText else { return }
        append(string)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "w:t": inText = false
        case "w:r": bold = false; italic = false; size = defaultSize
        case "w:p": if result.length > 0 { result.append(NSAttributedString(string: "\n")) }
        default: break
        }
        if stack.last == elementName { stack.removeLast() }
    }
}
