//
//  PDFTextBridge.swift
//  FurAffinityUI (Android)
//
//  Native-Swift driver for the Kotlin `FAPDFTextBridge` (PdfBox-Android), reached by
//  class name through SkipBridge's `AnyDynamicObject` like `MediaBridge`.
//
//  Unguarded on purpose — an Android substitution file must be, see
//  Android/docs/shared-sources.md § Rules for shared sources. The JNI inside is `canImport(Android)`-guarded.
//

import Foundation
import FAKit
#if canImport(Android)
import SkipBridge
#endif

enum PDFTextBridge {
    private struct Document: Decodable {
        struct Page: Decodable {
            struct Image: Decodable {
                var top: Double
                var path: String
            }

            var width: Double
            var height: Double
            var text: String
            var runs: [Run]
            var boxes: [Double]
            var images: [Image]
        }

        var pages: [Page]
    }

    private struct Run: Decodable {
        var length: Int
        var size: Double
        var bold: Bool
        var italic: Bool
    }

    static func pages(fileUrl: URL) async -> [PDFPageText]? {
        #if canImport(Android)
        let imageDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdf-images-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: imageDir) }
        let json: String = await callBridgeOffPool("FAPDFTextBridge", qos: .userInitiated, fallback: "") { bridge in
            let json: String? = try bridge.pages(fileUrl.path, imageDir.path)
            return json ?? ""
        }
        guard let data = json.data(using: .utf8), !data.isEmpty else { return nil }
        do {
            return try JSONDecoder().decode(Document.self, from: data).pages.map(pageText)
        } catch {
            logger.error("PDFTextBridge: undecodable pages for \(fileUrl.lastPathComponent): \(error)")
            return nil
        }
        #else
        return nil
        #endif
    }

    private static func pageText(_ page: Document.Page) -> PDFPageText {
        let runs = page.runs.map { run in
            (length: run.length, font: StoryFont(size: CGFloat(run.size), bold: run.bold, italic: run.italic))
        }
        let bounds = stride(from: 0, to: page.boxes.count - 3, by: 4).map { i in
            Foundation.CGRect(x: page.boxes[i], y: page.boxes[i + 1], width: page.boxes[i + 2], height: page.boxes[i + 3])
        }
        let images = page.images.compactMap { image -> (top: CGFloat, png: Data)? in
            (try? Data(contentsOf: URL(fileURLWithPath: image.path))).map { (CGFloat(image.top), $0) }
        }
        return PDFPageText(
            text: page.text,
            runs: runs,
            characterBounds: bounds,
            mediaBox: Foundation.CGRect(x: 0, y: 0, width: page.width, height: page.height),
            images: images
        )
    }
}
