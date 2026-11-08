//
//  StoryDocument+UIKit.swift
//  FAKit
//
//  Created by Ceylo on 21/06/2026.
//

#if !os(Android)

import Foundation
import UIKit

extension StoryDocument {
    public static func richText(from data: Data, filename: String) -> AttributedString? {
        // RTF keeps the system importer's fonts as they are.
        if (filename as NSString).pathExtension.lowercased() == "rtf" {
            return systemRTFText(from: data).map { AttributedString($0) }
        }
        let pdfPages = (filename as NSString).pathExtension.lowercased() == "pdf"
            ? PDFKitPageSource.pages(from: data) : nil
        return neutralText(from: data, filename: filename, pdfPages: pdfPages)
            .map { AttributedString(uiKitText($0)) }
    }

    static func systemRTFText(from data: Data) -> NSAttributedString? {
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

    static func neutralized(_ text: NSAttributedString) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(string: text.string)
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            var neutral: [NSAttributedString.Key: Any] = [:]
            if let font = attributes[.font] as? UIFont {
                let traits = font.fontDescriptor.symbolicTraits
                neutral[.storyFont] = StoryFont(
                    size: font.pointSize,
                    bold: traits.contains(.traitBold),
                    italic: traits.contains(.traitItalic),
                    name: font.fontName
                )
            }
            if (attributes[.paragraphStyle] as? NSParagraphStyle)?.alignment == .center {
                neutral[.storyCentered] = true
            }
            result.setAttributes(neutral, range: range)
        }
        return result
    }

    static func uiKitText(_ text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text.string)
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
            var uiKit: [NSAttributedString.Key: Any] = [:]
            if let font = attributes[.storyFont] as? StoryFont {
                uiKit[.font] =
                    font.name.flatMap { UIFont(name: $0, size: font.size) }
                    ?? UIFont.font(ofSize: font.size, bold: font.bold, italic: font.italic)
            }
            if attributes[.storyCentered] as? Bool == true {
                let style = NSMutableParagraphStyle()
                style.alignment = .center
                uiKit[.paragraphStyle] = style
            }
            if let png = attributes[.storyImage] as? Data, let image = UIImage(data: png) {
                let attachment = FittingImageTextAttachment()
                attachment.image = image
                uiKit[.attachment] = attachment
            }
            result.setAttributes(uiKit, range: range)
        }
        return result
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

#endif
