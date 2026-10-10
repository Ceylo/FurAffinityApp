//
//  FAImageHeader.swift
//  FAKit
//
//  An image's pixel size, read from its header alone: no decoding, so it costs the same
//  on both platforms and is unit-testable on both. Covers what FA serves — PNG, GIF,
//  JPEG and WebP.
//

import Foundation

enum FAImageHeader {
    static func pixelSize(of data: Data) -> CGSize? {
        let bytes = [UInt8](data.prefix(256 * 1024))
        return png(bytes) ?? gif(bytes) ?? jpeg(bytes) ?? webp(bytes)
    }

    private static func png(_ b: [UInt8]) -> CGSize? {
        // Signature, then the IHDR chunk: length, "IHDR", width, height.
        guard b.count >= 24, b.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
              b[12...15].elementsEqual("IHDR".utf8) else { return nil }
        return size(bigEndian32(b, 16), bigEndian32(b, 20))
    }

    private static func gif(_ b: [UInt8]) -> CGSize? {
        // "GIF87a" or "GIF89a", then the logical screen's width and height.
        guard b.count >= 10, b[0...2].elementsEqual("GIF".utf8) else { return nil }
        return size(littleEndian16(b, 6), littleEndian16(b, 8))
    }

    private static func jpeg(_ b: [UInt8]) -> CGSize? {
        guard b.count >= 4, b[0] == 0xFF, b[1] == 0xD8 else { return nil }
        var i = 2
        while i + 3 < b.count {
            guard b[i] == 0xFF else { return nil }
            let marker = b[i + 1]
            // Fill bytes before a marker.
            if marker == 0xFF { i += 1; continue }
            // Markers with no length: TEM and RST0–7.
            if marker == 0x01 || (0xD0...0xD7).contains(marker) { i += 2; continue }
            let length = Int(b[i + 2]) << 8 | Int(b[i + 3])
            // SOF0–15, minus DHT (C4), JPG (C8) and DAC (CC), which share the range.
            if (0xC0...0xCF).contains(marker), ![0xC4, 0xC8, 0xCC].contains(marker) {
                guard i + 8 < b.count else { return nil }
                let height = Int(b[i + 5]) << 8 | Int(b[i + 6])
                let width = Int(b[i + 7]) << 8 | Int(b[i + 8])
                return size(width, height)
            }
            guard length >= 2 else { return nil }
            i += 2 + length
        }
        return nil
    }

    private static func webp(_ b: [UInt8]) -> CGSize? {
        guard b.count >= 30, b[0...3].elementsEqual("RIFF".utf8),
              b[8...11].elementsEqual("WEBP".utf8) else { return nil }
        switch String(decoding: b[12...15], as: UTF8.self) {
        case "VP8 ":
            // Lossy: a 3-byte frame tag, the 9D 01 2A start code, then 14-bit sizes.
            guard b[23] == 0x9D, b[24] == 0x01, b[25] == 0x2A else { return nil }
            return size(littleEndian16(b, 26) & 0x3FFF, littleEndian16(b, 28) & 0x3FFF)
        case "VP8L":
            // Lossless: a 0x2F signature, then width-1 and height-1 as 14-bit fields.
            guard b[20] == 0x2F else { return nil }
            let bits = Int(b[21]) | Int(b[22]) << 8 | Int(b[23]) << 16 | Int(b[24]) << 24
            return size((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1)
        case "VP8X":
            // Extended: 24-bit canvas width-1 and height-1.
            let width = Int(b[24]) | Int(b[25]) << 8 | Int(b[26]) << 16
            let height = Int(b[27]) | Int(b[28]) << 8 | Int(b[29]) << 16
            return size(width + 1, height + 1)
        default:
            return nil
        }
    }

    private static func size(_ width: Int, _ height: Int) -> CGSize? {
        guard width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    private static func bigEndian32(_ b: [UInt8], _ i: Int) -> Int {
        Int(b[i]) << 24 | Int(b[i + 1]) << 16 | Int(b[i + 2]) << 8 | Int(b[i + 3])
    }

    private static func littleEndian16(_ b: [UInt8], _ i: Int) -> Int {
        Int(b[i]) | Int(b[i + 1]) << 8
    }
}
