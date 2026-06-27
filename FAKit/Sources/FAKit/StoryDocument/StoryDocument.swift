//
//  StoryDocument.swift
//  FAKit
//
//  Created by Ceylo on 21/06/2026.
//

import Foundation
import UIKit

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
            ns = PDFReflow.text(from: data, bodyPointSize: bodyPointSize)
        case "docx":
            ns = DocxTextParser.text(from: data)
        default:
            ns = nil
        }
        return ns.map { AttributedString($0) }
    }

    private static func plainAttributed(_ string: String) -> NSAttributedString {
        NSAttributedString(
            string: string,
            attributes: [.font: UIFont.systemFont(ofSize: bodyPointSize)]
        )
    }

    private static func rtfText(from data: Data) -> NSAttributedString? {
        guard
            let attributed = try? NSMutableAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
        else { return nil }

        // Drop baked-in colors so the reader's `.label` keeps dark mode readable.
        attributed.removeAttribute(.foregroundColor, range: NSRange(location: 0, length: attributed.length))
        return attributed.length > 0 ? attributed : nil
    }
}

extension UIFont {
    static func font(ofSize size: CGFloat, bold: Bool, italic: Bool) -> UIFont {
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        let base = UIFont.systemFont(ofSize: size)
        guard !traits.isEmpty,
            let descriptor = base.fontDescriptor.withSymbolicTraits(traits)
        else {
            return base
        }
        return UIFont(descriptor: descriptor, size: size)
    }
}

/// A text attachment that sizes its image to the available line-fragment width at
/// layout time — never upscaling, preserving aspect ratio. Sizing at layout avoids the
/// zero-width first-layout problem of sizing against the text view's bounds.
final class FittingImageTextAttachment: NSTextAttachment {
    private func fittedBounds(proposedWidth: CGFloat) -> CGRect {
        guard let image, image.size.width > 0 else { return .zero }
        let maxWidth = proposedWidth > 0 ? proposedWidth : image.size.width
        let factor = min(1, maxWidth / image.size.width)
        return CGRect(x: 0, y: 0, width: image.size.width * factor, height: image.size.height * factor)
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        fittedBounds(proposedWidth: proposedLineFragment.width)
    }

    override func attachmentBounds(
        for textContainer: NSTextContainer?,
        proposedLineFragment lineFrag: CGRect,
        glyphPosition position: CGPoint,
        characterIndex charIndex: Int
    ) -> CGRect {
        fittedBounds(proposedWidth: lineFrag.width)
    }
}
