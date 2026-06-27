//
//  DocxTextParser.swift
//  FurAffinity
//
//  Created by Ceylo on 27/06/2026.
//


import Foundation
import UIKit
import PDFKit
import ZIPFoundation

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