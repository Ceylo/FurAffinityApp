//
//  StoryDocument.swift
//  FAKit
//
//  Created by Ceylo on 21/06/2026.
//

import Foundation

public typealias PDFPageSource = @Sendable (Data) -> [PDFPageText]?

/// Extracts readable rich text from a downloaded story-submission document so it can be
/// rendered as native, reflowing text while keeping bold/italic, relative font sizes and
/// paragraph structure. Returns `nil` for formats we can't read.
///
/// Runs carry only fonts (size + traits), never a color, so the reader stays correct in
/// light/dark mode. Sizes are relative to ``bodyPointSize``; the reader normalizes them to
/// its own body size.
public enum StoryDocument {
    /// Reference body size; heading/emphasis runs use multiples of this. The reader
    /// normalizes against the document's dominant size, so the absolute value only
    /// matters as a common baseline across formats.
    static let bodyPointSize: CGFloat = 17

    #if os(Android)
    public static let defaultPDFPages: PDFPageSource? = nil
    #else
    public static let defaultPDFPages: PDFPageSource? = PDFKitPageSource.pages
    #endif

    public static func paragraphs(
        from data: Data,
        filename: String,
        pdfPages: PDFPageSource? = defaultPDFPages
    ) -> [StoryParagraph]? {
        neutralText(from: data, filename: filename, pdfPages: pdfPages).map {
            StoryParagraph.paragraphs(from: $0, bodyPointSize: bodyPointSize)
        }
    }

    static func neutralText(from data: Data, filename: String, pdfPages: PDFPageSource?) -> NSAttributedString? {
        if let text = StoryText.text(from: data, filename: filename) {
            return NSAttributedString(string: text, attributes: [.storyFont: StoryFont(size: bodyPointSize)])
        }
        switch (filename as NSString).pathExtension.lowercased() {
        case "pdf":
            return pdfPages?(data).flatMap { PDFReflow.text(from: $0, bodyPointSize: bodyPointSize) }
        case "docx":
            return DocxTextParser.text(from: data)
        case "rtf":
            #if os(Android)
            return nil
            #else
            return systemRTFText(from: data).map(neutralized)
            #endif
        default:
            return nil
        }
    }
}
