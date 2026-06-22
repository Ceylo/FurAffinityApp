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

        let indentParagraphs = documentUsesFirstLineIndent(document)

        let result = NSMutableAttributedString()
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            appendReflowed(page: page, to: result, indentParagraphs: indentParagraphs)
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
        /// False when no character reported usable geometry; the text is still kept
        /// but the line can't take part in the line-fill test.
        var hasBounds: Bool
        var height: CGFloat { maxY - minY }
        var firstWordWidth: CGFloat { firstWordMaxX - firstWordMinX }
    }

    /// How two consecutive visual lines are joined when reflowing a PDF page.
    private enum LineJoin {
        /// Same paragraph, wrapped by width — join with a space (de-hyphenating).
        case softWrap
        /// A new paragraph — gets the reader's paragraph spacing.
        case paragraph
        /// Not a real break: PDFKit split one logical word/row in two (typically at a
        /// curly apostrophe) — join the fragments with nothing between them.
        case noSeparator
    }

    /// Per-page horizontal/vertical reference values derived from the bounded lines.
    private struct PageMetrics {
        var medianHeight: CGFloat
        var bodyRight: CGFloat
        var leftMargin: CGFloat
        var spaceWidth: CGFloat
        var indentThreshold: CGFloat
        var pageMidX: CGFloat
    }

    /// PDFKit's per-character text for a page, split into visual lines (it emits a `\n`
    /// per line) with each line's on-page geometry.
    private static func visualLines(of page: PDFPage) -> (attributed: NSAttributedString, lines: [PDFLine]) {
        let attributed = page.attributedString ?? NSAttributedString()
        let string = attributed.string as NSString
        let count = min(string.length, page.numberOfCharacters)
        var lines: [PDFLine] = []
        guard count > 0 else { return (attributed, lines) }

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
                if !hasBounds { minX = 0; maxX = 0; minY = 0; maxY = 0 }
                if !firstWordStarted { firstWordMinX = minX; firstWordMaxX = maxX }
                lines.append(PDFLine(range: NSRange(location: lineStart, length: length),
                                     minX: minX, maxX: maxX, minY: minY, maxY: maxY,
                                     firstWordMinX: firstWordMinX, firstWordMaxX: firstWordMaxX,
                                     hasBounds: hasBounds))
            }
            lineStart = end + 1
        }
        for i in 0..<count where Unicode.Scalar(string.character(at: i)) == "\n" {
            flushLine(end: i)
        }
        flushLine(end: count)
        return (attributed, lines)
    }

    private static func metrics(for lines: [PDFLine], page: PDFPage) -> PageMetrics {
        let bounded = lines.filter(\.hasBounds)
        let medianHeight = median(bounded.map(\.height)) ?? bodyPointSize
        return PageMetrics(
            medianHeight: medianHeight,
            bodyRight: bounded.map(\.maxX).max() ?? 0,
            leftMargin: bounded.map(\.minX).min() ?? 0,
            spaceWidth: medianHeight * 0.25,
            indentThreshold: max(medianHeight, 12),
            pageMidX: page.bounds(for: .mediaBox).midX)
    }

    /// Decides whether the document indents the first line of each paragraph (restore a
    /// tab) versus separating paragraphs by spacing only. Per-character geometry is noisy,
    /// so we vote: a likely paragraph-start line counts as indented when its left edge
    /// sits a clear step right of the body's left margin. Block-style documents reliably
    /// score zero indented starts; indent-style documents score enough to win.
    private static func documentUsesFirstLineIndent(_ document: PDFDocument) -> Bool {
        var indented = 0, total = 0
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let (attributed, lines) = visualLines(of: page)
            guard lines.count > 1 else { continue }
            let m = metrics(for: lines, page: page)
            for i in 1..<lines.count {
                let line = lines[i], previous = lines[i - 1]
                guard line.hasBounds, previous.hasBounds else { continue }
                let substring = attributed.attributedSubstring(from: line.range)
                // Geometry-only paragraph-start guess: the previous line ended early and
                // this one opens like a paragraph (not a wrapped continuation, not centered).
                let endedEarly = m.bodyRight - previous.maxX >= m.spaceWidth + line.firstWordWidth
                guard endedEarly, !beginsLikeContinuation(substring),
                      !isCentered(line, pageMidX: m.pageMidX, leftMargin: m.leftMargin) else { continue }
                total += 1
                if line.minX - m.leftMargin >= m.indentThreshold { indented += 1 }
            }
        }
        return indented >= 2 && indented * 3 >= total
    }

    /// Reconstructs paragraphs from a PDF page: PDFKit already breaks the text into
    /// visual lines (a `\n` per line, which is what shows orphaned words on screen).
    /// A break is a *soft wrap* (rejoined with a space) when the previous line was
    /// full — the next line's leading word wouldn't have fit (line-fill test);
    /// otherwise the line ended early on purpose and starts a new *paragraph*. This
    /// keeps short title lines on their own and detects paragraph ends regardless of
    /// vertical spacing. Lines whose glyphs report no geometry still have their text
    /// emitted (joined as a soft wrap) so no words are lost. Original per-character
    /// fonts (size + traits) are preserved. When the document indents the first line of
    /// each paragraph, restore that indent as a leading tab.
    private static func appendReflowed(page: PDFPage, to result: NSMutableAttributedString, indentParagraphs: Bool) {
        let (attributed, lines) = visualLines(of: page)

        // Embedded illustrations, kept in reading order by their top edge (PDF y-up).
        let images = embeddedImages(on: page).sorted { $0.top > $1.top }
        var nextImage = 0
        func emitImages(above top: CGFloat) {
            while nextImage < images.count, images[nextImage].top >= top {
                appendImage(images[nextImage].image, to: result)
                nextImage += 1
            }
        }

        guard !lines.isEmpty || !images.isEmpty else { return }

        let m = metrics(for: lines, page: page)
        let bodyRight = m.bodyRight
        let leftMargin = m.leftMargin
        let spaceWidth = m.spaceWidth
        let pageMidX = m.pageMidX

        for (index, line) in lines.enumerated() {
            emitImages(above: line.maxY)
            let substring = attributed.attributedSubstring(from: line.range)
            let centered = line.hasBounds && isCentered(line, pageMidX: pageMidX, leftMargin: leftMargin)

            let join: LineJoin
            if index == 0 {
                // First line of a later page continues as a new paragraph.
                join = result.length > 0 ? .paragraph : .softWrap
            } else {
                let previous = lines[index - 1]
                let previousCentered = previous.hasBounds && isCentered(previous, pageMidX: pageMidX, leftMargin: leftMargin)
                let head = firstNonSpaceScalar(in: substring)
                let openingQuote = head == "\u{201C}" || head == "\u{2018}"
                if openingQuote, !endsMidClause(result) {
                    // An opening quote that doesn't continue an unfinished clause starts a
                    // new dialogue turn → its own paragraph, even when the line reports no
                    // usable geometry. A quote after a line ending mid-clause (e.g.
                    // `…the` + `“experiments”`) is a wrapped quoted word, not a new turn.
                    join = .paragraph
                } else if isSpuriousSplit(previous: previous, line: line, next: substring,
                                          result: result, spaceWidth: spaceWidth) {
                    // PDFKit broke one logical row/word in two (e.g. at a curly apostrophe);
                    // rejoin without a separator so contractions stay whole.
                    join = .noSeparator
                } else if centered || previousCentered {
                    // Centered title/byline lines stand alone, and the first body line
                    // after a centered block opens a new paragraph.
                    join = .paragraph
                } else if line.hasBounds, previous.hasBounds,
                          previous.minY - line.maxY > m.medianHeight {
                    // A roughly blank line of vertical space separates two blocks (e.g. a
                    // heading from the body) → new paragraph. Tall, noisy lines overlap and
                    // give negative gaps, so they don't trigger false breaks.
                    join = .paragraph
                } else if !line.hasBounds || !previous.hasBounds {
                    // Line-fill test: if the previous line had room for this line's first
                    // word (plus a space), it ended early on purpose → new paragraph;
                    // otherwise it was full → soft wrap we rejoin. Without geometry on
                    // either line we can't tell, so default to a soft wrap.
                    join = .softWrap
                } else {
                    // A new paragraph needs both room on the previous line *and* a line
                    // that reads like a paragraph opening — one starting with a lowercase
                    // letter is a soft-wrapped continuation, not a new paragraph (these
                    // PDFs' noisy geometry otherwise mistakes short wrapped lines for
                    // paragraph starts).
                    let available = bodyRight - previous.maxX
                    let nextWordWouldFit = available >= spaceWidth + line.firstWordWidth
                    join = nextWordWouldFit && !beginsLikeContinuation(substring) ? .paragraph : .softWrap
                }
            }

            // In a document that indents the first line of each paragraph, restore that
            // indent as a leading tab — matching the DOCX `<w:tab>` path. Centered lines
            // get alignment instead, never a tab.
            let isParagraphStart = join == .paragraph || (index == 0 && result.length == 0)
            let indented = indentParagraphs && isParagraphStart && !centered

            let emitted = indented ? prependingTab(to: substring) : substring
            appendSeparated(emitted, to: result, join: join)

            // A line centered on the page keeps centered alignment (e.g. a title); the
            // reader preserves it. Apply it to the emitted content only, not the leading
            // separator, which belongs to the previous paragraph.
            if centered, emitted.length > 0 {
                let range = NSRange(location: result.length - emitted.length, length: emitted.length)
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                result.addAttribute(.paragraphStyle, value: style, range: range)
            }
        }

        // Any images sitting below the last line of text (or all images on an
        // illustration-only page).
        emitImages(above: -.greatestFiniteMagnitude)
    }

    /// Appends `image` as its own centered paragraph via a text attachment. The reader
    /// sizes the attachment to the text width; here we only carry the image.
    private static func appendImage(_ image: UIImage, to result: NSMutableAttributedString) {
        if result.length > 0 {
            result.append(NSAttributedString(string: "\n"))
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        let start = result.length
        result.append(NSAttributedString(attachment: attachment))
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: start, length: result.length - start))
        result.append(NSAttributedString(string: "\n"))
    }

    /// Extracts each embedded raster image on the page as a rendered `UIImage` paired
    /// with the top edge of its on-page rectangle (PDF y-up), for interleaving with text.
    private static func embeddedImages(on page: PDFPage) -> [(top: CGFloat, image: UIImage)] {
        imagePlacements(on: page).compactMap { rect in
            renderImage(from: page, rect: rect).map { (rect.maxY, $0) }
        }
    }

    /// The on-page rectangles (PDF coordinates) where image XObjects are drawn, found by
    /// scanning the page content stream (`cm` updates the CTM, `Do` draws a unit square
    /// transformed by it). Returns an empty list when the page draws no images.
    private static func imagePlacements(on page: PDFPage) -> [CGRect] {
        guard let cgPage = page.pageRef else { return [] }
        let imageNames = imageXObjectNames(of: cgPage)
        guard !imageNames.isEmpty else { return [] }

        let scanner = PDFImageScanner(imageNames: imageNames)
        guard let table = CGPDFOperatorTableCreate() else { return [] }
        defer { CGPDFOperatorTableRelease(table) }

        CGPDFOperatorTableSetCallback(table, "q") { _, info in
            let s = Unmanaged<PDFImageScanner>.fromOpaque(info!).takeUnretainedValue()
            s.stack.append(s.ctm)
        }
        CGPDFOperatorTableSetCallback(table, "Q") { _, info in
            let s = Unmanaged<PDFImageScanner>.fromOpaque(info!).takeUnretainedValue()
            if let last = s.stack.popLast() { s.ctm = last }
        }
        CGPDFOperatorTableSetCallback(table, "cm") { scanner, info in
            let s = Unmanaged<PDFImageScanner>.fromOpaque(info!).takeUnretainedValue()
            var values = [CGFloat](repeating: 0, count: 6)
            for i in (0..<6).reversed() {
                var number: CGPDFReal = 0
                guard CGPDFScannerPopNumber(scanner, &number) else { return }
                values[i] = CGFloat(number)
            }
            let matrix = CGAffineTransform(a: values[0], b: values[1], c: values[2],
                                           d: values[3], tx: values[4], ty: values[5])
            s.ctm = matrix.concatenating(s.ctm)
        }
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            let s = Unmanaged<PDFImageScanner>.fromOpaque(info!).takeUnretainedValue()
            var name: UnsafePointer<Int8>?
            guard CGPDFScannerPopName(scanner, &name), let name,
                  s.imageNames.contains(String(cString: name)) else { return }
            s.placements.append(CGRect(x: 0, y: 0, width: 1, height: 1).applying(s.ctm))
        }

        let stream = CGPDFContentStreamCreateWithPage(cgPage)
        let cgScanner = CGPDFScannerCreate(stream, table, Unmanaged.passUnretained(scanner).toOpaque())
        CGPDFScannerScan(cgScanner)
        CGPDFScannerRelease(cgScanner)
        CGPDFContentStreamRelease(stream)
        return scanner.placements
    }

    /// Names of the page's XObjects whose subtype is `Image`.
    private static func imageXObjectNames(of page: CGPDFPage) -> Set<String> {
        guard let dictionary = page.dictionary else { return [] }
        var resources: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(dictionary, "Resources", &resources), let resources else { return [] }
        var xobjects: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(resources, "XObject", &xobjects), let xobjects else { return [] }

        final class Collector { var names = Set<String>() }
        let collector = Collector()
        CGPDFDictionaryApplyFunction(xobjects, { key, value, info in
            let collector = Unmanaged<Collector>.fromOpaque(info!).takeUnretainedValue()
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(value, .stream, &stream), let stream,
                  let streamDict = CGPDFStreamGetDictionary(stream) else { return }
            var subtype: UnsafePointer<Int8>?
            if CGPDFDictionaryGetName(streamDict, "Subtype", &subtype), let subtype,
               String(cString: subtype) == "Image" {
                collector.names.insert(String(cString: key))
            }
        }, Unmanaged.passUnretained(collector).toOpaque())
        return collector.names
    }

    /// Renders the given page rectangle (PDF coordinates) to a `UIImage` at `scale`× — a
    /// robust way to capture an embedded image regardless of its encoding or masks.
    private static func renderImage(from page: PDFPage, rect: CGRect, scale: CGFloat = 2) -> UIImage? {
        let width = Int((rect.width * scale).rounded()), height = Int((rect.height * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage().map { UIImage(cgImage: $0) }
    }

    /// The first non-whitespace Unicode scalar of an attributed string, if any.
    private static func firstNonSpaceScalar(in substring: NSAttributedString) -> Unicode.Scalar? {
        let string = substring.string as NSString
        var index = 0
        while index < string.length {
            guard let scalar = Unicode.Scalar(string.character(at: index)) else { return nil }
            if !CharacterSet.whitespaces.contains(scalar) { return scalar }
            index += 1
        }
        return nil
    }

    /// True when the already-emitted text ends mid-clause — its last non-space scalar is a
    /// lowercase letter — so the next line is a wrapped continuation rather than a new
    /// block. Lines ending in punctuation, a quote, or a capital read as finished.
    private static func endsMidClause(_ result: NSMutableAttributedString) -> Bool {
        let string = result.string as NSString
        var index = string.length - 1
        while index >= 0 {
            guard let scalar = Unicode.Scalar(string.character(at: index)) else { return false }
            if !CharacterSet.whitespacesAndNewlines.contains(scalar) {
                return CharacterSet.lowercaseLetters.contains(scalar)
            }
            index -= 1
        }
        return false
    }

    /// True when a line reads like the continuation of a wrapped sentence rather than a
    /// new paragraph — i.e. it starts with a lowercase letter. Paragraphs open with a
    /// capital, an opening quote, or a digit/symbol.
    private static func beginsLikeContinuation(_ substring: NSAttributedString) -> Bool {
        guard let scalar = firstNonSpaceScalar(in: substring) else { return false }
        return CharacterSet.lowercaseLetters.contains(scalar)
    }

    /// True when a line is centered on the page (its midpoint sits at the page center and
    /// it does not start at the body's left margin) — e.g. a centered title.
    private static func isCentered(_ line: PDFLine, pageMidX: CGFloat, leftMargin: CGFloat) -> Bool {
        guard line.hasBounds else { return false }
        let mid = (line.minX + line.maxX) / 2
        return abs(mid - pageMidX) <= 12 && line.minX > leftMargin + 12
    }

    /// Prepends a tab carrying `substring`'s leading run attributes, so a first-line
    /// indent renders without inflating the line height.
    private static func prependingTab(to substring: NSAttributedString) -> NSAttributedString {
        guard substring.length > 0 else { return substring }
        let result = NSMutableAttributedString(string: "\t", attributes: substring.attributes(at: 0, effectiveRange: nil))
        result.append(substring)
        return result
    }

    /// True when two consecutive PDFKit "lines" are really one logical row or word that
    /// PDFKit split — it inserts a newline at curly-quote/apostrophe font runs. Two
    /// independent signals: the fragment continues rightward on the *same row*
    /// (geometry), or it completes a *contraction* across the break (an apostrophe with a
    /// lowercase tail). The lowercase tail keeps real dialogue lines — which open with a
    /// capital or an opening quote `“`/`‘` — from being merged.
    private static func isSpuriousSplit(previous: PDFLine, line: PDFLine,
                                        next substring: NSAttributedString,
                                        result: NSMutableAttributedString,
                                        spaceWidth: CGFloat) -> Bool {
        // Same row, continuing to the right of where the previous fragment ended — but
        // only when the fragment continues a word (its first non-space scalar is a
        // lowercase letter or an apostrophe). This keeps the lone-apostrophe merge
        // (`There` + `’`) while no longer merging an adjacent dialogue turn, which opens
        // with a capital or an opening quote.
        if line.hasBounds, previous.hasBounds,
           line.minX >= previous.maxX - spaceWidth,
           line.minY < previous.maxY, previous.minY < line.maxY,
           let head = firstNonSpaceScalar(in: substring),
           CharacterSet.lowercaseLetters.contains(head) || head == "\u{2019}" || head == "'" {
            return true
        }

        // A fragment that begins with clause punctuation can't start a real line —
        // PDFKit split a clause at an adjacent quote (e.g. `…"normal"` + `, but …`,
        // `…"experiments"` + `. And …`). Attach it with no separator.
        if let head = firstNonSpaceScalar(in: substring), ",.;:".unicodeScalars.contains(head) {
            return true
        }

        // Contraction split at an apostrophe: "It’" + "s …", or "don" + "’t …".
        guard result.length > 0 else { return false }
        let prevString = result.string as NSString
        let prevChar = Unicode.Scalar(prevString.character(at: prevString.length - 1))
        let nextString = substring.string as NSString
        guard nextString.length > 0 else { return false }
        let nextChar = Unicode.Scalar(nextString.character(at: 0))

        func isApostrophe(_ scalar: Unicode.Scalar?) -> Bool { scalar == "\u{2019}" || scalar == "'" }
        func isLowercaseLetter(_ scalar: Unicode.Scalar?) -> Bool {
            guard let scalar else { return false }
            return CharacterSet.lowercaseLetters.contains(scalar)
        }

        // prev ends with an apostrophe, next starts lowercase: "It’" + "s".
        if isApostrophe(prevChar), isLowercaseLetter(nextChar) { return true }
        // prev ends with a letter, next is apostrophe + lowercase: "don" + "’t".
        if let prevChar, CharacterSet.letters.contains(prevChar), isApostrophe(nextChar),
           nextString.length >= 2, isLowercaseLetter(Unicode.Scalar(nextString.character(at: 1))) {
            return true
        }
        return false
    }

    /// Appends `substring` to `result`, separating it from the existing text per
    /// `join`: a paragraph break (`\n`) or a soft-wrap space — joining hyphenated
    /// words without the hyphen.
    private static func appendSeparated(_ substring: NSAttributedString, to result: NSMutableAttributedString, join: LineJoin) {
        if result.length == 0 {
            result.append(substring)
            return
        }
        // Separators inherit the preceding run's font so they don't inflate the line
        // height (an oversized join space would make that display line taller).
        let separatorAttributes = result.attributes(at: result.length - 1, effectiveRange: nil)
        switch join {
        case .paragraph:
            result.append(NSAttributedString(string: "\n", attributes: separatorAttributes))
            result.append(substring)
            return
        case .noSeparator:
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
            result.append(NSAttributedString(string: " ", attributes: separatorAttributes))
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

/// Mutable state threaded through the content-stream scan that locates image draws:
/// the current transform, the graphics-state stack, and the collected image rectangles.
private final class PDFImageScanner {
    let imageNames: Set<String>
    var ctm = CGAffineTransform.identity
    var stack: [CGAffineTransform] = []
    var placements: [CGRect] = []

    init(imageNames: Set<String>) { self.imageNames = imageNames }
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
