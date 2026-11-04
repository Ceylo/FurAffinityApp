//
//  PDFKitPageSource.swift
//  FAKit
//
//  Created by Ceylo on 27/06/2026.
//

#if !os(Android)

import Foundation
import PDFKit
import UIKit

enum PDFKitPageSource {
    static func pages(from data: Data) -> [PDFPageText]? {
        registerBundledFonts()
        guard let document = PDFDocument(data: data) else { return nil }
        return (0..<document.pageCount).compactMap { index in
            document.page(at: index).map(pageText)
        }
    }

    private static func pageText(_ page: PDFPage) -> PDFPageText {
        let text = StoryDocument.neutralized(page.attributedString ?? NSAttributedString())
        let count = min(text.length, page.numberOfCharacters)
        return PDFPageText(
            text: text,
            characterBounds: (0..<count).map { page.characterBounds(at: $0) },
            mediaBox: page.bounds(for: .mediaBox),
            images: imagePlacements(on: page).compactMap { rect in
                renderImage(from: page, rect: rect).map { (rect.maxY, $0) }
            }
        )
    }

    /// Registers the bundled Roboto faces with the process once. iOS doesn't ship
    /// Roboto, so PDFKit otherwise substitutes it with Helvetica and drops the
    /// embedded bold/italic faces — making Roboto-based comic PDFs (e.g. LIMA) lose
    /// their emphasis. With the faces registered, PDFKit matches them by PostScript
    /// name and the run traits survive into the reflow.
    private static let bundledFontsRegistered: Void = {
        guard let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: nil) else { return }
        for url in urls {
            var error: Unmanaged<CFError>?
            // Already-registered is fine (the static runs once, but be defensive).
            if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error),
                let error = error?.takeRetainedValue()
            {
                logger.error("Failed to register bundled font \(url.lastPathComponent): \(error)")
            }
        }
    }()

    private static func registerBundledFonts() { _ = bundledFontsRegistered }

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
            let matrix = CGAffineTransform(
                a: values[0],
                b: values[1],
                c: values[2],
                d: values[3],
                tx: values[4],
                ty: values[5]
            )
            s.ctm = matrix.concatenating(s.ctm)
        }
        CGPDFOperatorTableSetCallback(table, "Do") { scanner, info in
            let s = Unmanaged<PDFImageScanner>.fromOpaque(info!).takeUnretainedValue()
            var name: UnsafePointer<Int8>?
            guard CGPDFScannerPopName(scanner, &name), let name,
                s.imageNames.contains(String(cString: name))
            else { return }
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
        CGPDFDictionaryApplyFunction(
            xobjects,
            { key, value, info in
                let collector = Unmanaged<Collector>.fromOpaque(info!).takeUnretainedValue()
                var stream: CGPDFStreamRef?
                guard CGPDFObjectGetValue(value, .stream, &stream), let stream,
                    let streamDict = CGPDFStreamGetDictionary(stream)
                else { return }
                var subtype: UnsafePointer<Int8>?
                if CGPDFDictionaryGetName(streamDict, "Subtype", &subtype), let subtype,
                    String(cString: subtype) == "Image"
                {
                    collector.names.insert(String(cString: key))
                }
            },
            Unmanaged.passUnretained(collector).toOpaque()
        )
        return collector.names
    }

    /// Renders the given page rectangle (PDF coordinates) to PNG data at `scale`× — a
    /// robust way to capture an embedded image regardless of its encoding or masks.
    private static func renderImage(from page: PDFPage, rect: CGRect, scale: CGFloat = 2) -> Data? {
        let width = Int((rect.width * scale).rounded())
        let height = Int((rect.height * scale).rounded())
        guard width > 0, height > 0,
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage().flatMap { UIImage(cgImage: $0).pngData() }
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

#endif
