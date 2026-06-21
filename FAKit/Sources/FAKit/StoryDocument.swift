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

/// Extracts readable plain text from a downloaded story-submission document so it
/// can be rendered as native, reflowing text. Returns `nil` for formats we can't
/// read (the caller should fall back to a document preview).
public enum StoryDocument {
    public static func plainText(from data: Data, filename: String) -> String? {
        switch (filename as NSString).pathExtension.lowercased() {
        case "txt", "text", "md":
            return String(data: data, encoding: .utf8)
        case "rtf":
            return rtfText(from: data)
        case "pdf":
            return pdfText(from: data)
        case "docx":
            return docxText(from: data)
        default:
            return nil
        }
    }

    private static func rtfText(from data: Data) -> String? {
        let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        return attributed?.string
    }

    private static func pdfText(from data: Data) -> String? {
        guard let text = PDFDocument(data: data)?.string else { return nil }
        return text.isEmpty ? nil : text
    }

    private static func docxText(from data: Data) -> String? {
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

        let text = delegate.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

/// Collects readable text from a Word `document.xml`: characters inside `<w:t>`,
/// paragraph breaks on `</w:p>`, line breaks on `<w:br>`, tabs on `<w:tab>`.
private final class DocxTextParser: NSObject, XMLParserDelegate {
    private(set) var text = ""
    private var inTextRun = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        switch elementName {
        case "w:t": inTextRun = true
        case "w:tab": text += "\t"
        case "w:br", "w:cr": text += "\n"
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inTextRun else { return }
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "w:t": inTextRun = false
        case "w:p": text += "\n\n"
        default: break
        }
    }
}
