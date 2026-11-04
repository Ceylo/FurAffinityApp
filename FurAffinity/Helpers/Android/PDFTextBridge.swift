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
            var runs: [[Run]]
            var boxes: [Double]
            var images: [Image]
        }

        var pages: [Page]
    }

    private enum Run: Decodable {
        case number(Double)
        case flag(Bool)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let flag = try? container.decode(Bool.self) {
                self = .flag(flag)
            } else {
                self = .number(try container.decode(Double.self))
            }
        }

        var number: Double {
            if case .number(let value) = self { return value }
            return 0
        }

        var flag: Bool {
            if case .flag(let value) = self { return value }
            return false
        }
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
        let runs = page.runs.compactMap { run -> (length: Int, font: StoryFont)? in
            guard run.count == 4 else { return nil }
            let font = StoryFont(size: CGFloat(run[1].number), bold: run[2].flag, italic: run[3].flag)
            return (Int(run[0].number), font)
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
