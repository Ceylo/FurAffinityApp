//
//  ZipEntryReader.swift
//  FAKit (Android)
//
//  Created by Ceylo on 04/11/2026.
//
//  ZIPFoundation can't be used here: its manifest picks its zlib target with
//  `canImport(Compression)`, which the macOS host answers, so an Android cross-build
//  lacks the `CZlib` module its sources import.
//

#if os(Android)

import Foundation
import zlib

enum ZipEntryReader {
    static func data(of path: String, in archive: Data) -> Data? {
        let bytes = [UInt8](archive)
        func u16(_ at: Int) -> Int? {
            at + 2 <= bytes.count ? Int(bytes[at]) | Int(bytes[at + 1]) << 8 : nil
        }
        func u32(_ at: Int) -> Int? {
            guard let low = u16(at), let high = u16(at + 2) else { return nil }
            return low | high << 16
        }

        guard bytes.count >= 22 else { return nil }
        guard let end = stride(from: bytes.count - 22, through: max(0, bytes.count - 65_557), by: -1)
            .first(where: { u32($0) == 0x0605_4b50 }),
            let count = u16(end + 10),
            var entry = u32(end + 16)
        else { return nil }

        let name = Array(path.utf8)
        for _ in 0..<count {
            guard u32(entry) == 0x0201_4b50,
                let method = u16(entry + 10),
                let compressedSize = u32(entry + 20),
                let size = u32(entry + 24),
                let nameLength = u16(entry + 28),
                let extraLength = u16(entry + 30),
                let commentLength = u16(entry + 32),
                let localHeader = u32(entry + 42),
                entry + 46 + nameLength <= bytes.count
            else { return nil }
            defer { entry += 46 + nameLength + extraLength + commentLength }
            guard bytes[(entry + 46)..<(entry + 46 + nameLength)].elementsEqual(name) else { continue }

            guard u32(localHeader) == 0x0403_4b50,
                let localNameLength = u16(localHeader + 26),
                let localExtraLength = u16(localHeader + 28)
            else { return nil }
            let start = localHeader + 30 + localNameLength + localExtraLength
            guard start + compressedSize <= bytes.count else { return nil }
            let compressed = bytes[start..<(start + compressedSize)]
            switch method {
            case 0: return Data(compressed)
            case 8: return inflate(Array(compressed), size: size)
            default: return nil
            }
        }
        return nil
    }

    private static func inflate(_ input: [UInt8], size: Int) -> Data? {
        var output = [UInt8](repeating: 0, count: size)
        var stream = z_stream()
        guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        defer { inflateEnd(&stream) }
        var input = input
        let status = input.withUnsafeMutableBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                stream.next_in = source.baseAddress
                stream.avail_in = uInt(source.count)
                stream.next_out = destination.baseAddress
                stream.avail_out = uInt(destination.count)
                return zlib.inflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END, Int(stream.total_out) == size else { return nil }
        return Data(output)
    }
}

#endif
