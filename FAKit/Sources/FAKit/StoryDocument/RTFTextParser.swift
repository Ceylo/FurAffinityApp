//
//  RTFTextParser.swift
//  FAKit
//
//  Created by Ceylo on 04/11/2026.
//

import Foundation

/// Android only: iOS keeps the system importer.
struct RTFTextParser {
    static func text(from data: Data) -> NSAttributedString? {
        var parser = RTFTextParser(bytes: [UInt8](data))
        guard parser.bytes.starts(with: Array("{\\rtf".utf8)) else { return nil }
        parser.parse()
        parser.flush()
        let result = PDFReflow.trimmed(parser.result)
        return result.length > 0 ? result : nil
    }

    private struct State {
        var bold = false
        var italic = false
        var halfPoints = 24
        var centered = false
        var skipped = false
        var unicodeSkip = 1
    }

    private static let skippedDestinations: Set<String> = [
        "fonttbl", "colortbl", "stylesheet", "info", "pict", "header", "headerl", "headerr",
        "headerf", "footer", "footerl", "footerr", "footerf", "listtable", "listoverridetable",
    ]

    private let bytes: [UInt8]
    private var index = 0
    private var state = State()
    private var stack: [State] = []
    private var codepage = 1252
    private var pendingSkip = 0
    private var highSurrogate: UInt16?

    private let result = NSMutableAttributedString(string: "")
    private var run = ""
    private var runFont = StoryFont(size: 12)
    private var runCentered = false

    private init(bytes: [UInt8]) { self.bytes = bytes }

    private mutating func parse() {
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            switch byte {
            case UInt8(ascii: "{"):
                stack.append(state)
            case UInt8(ascii: "}"):
                if let previous = stack.popLast() { state = previous }
            case UInt8(ascii: "\\"):
                controlSymbol()
            case UInt8(ascii: "\r"), UInt8(ascii: "\n"):
                break
            default:
                character(byte)
            }
        }
    }

    private mutating func controlSymbol() {
        guard index < bytes.count else { return }
        let byte = bytes[index]
        if isLetter(byte) {
            controlWord()
            return
        }
        index += 1
        switch byte {
        case UInt8(ascii: "'"):
            guard index + 2 <= bytes.count,
                let value = UInt8(String(decoding: bytes[index..<(index + 2)], as: UTF8.self), radix: 16)
            else { return }
            index += 2
            character(value)
        case UInt8(ascii: "*"):
            state.skipped = true
        case UInt8(ascii: "~"):
            emit("\u{00A0}")
        case UInt8(ascii: "_"):
            emit("\u{2011}")
        case UInt8(ascii: "\r"), UInt8(ascii: "\n"):
            emit("\n")
        case UInt8(ascii: "\\"), UInt8(ascii: "{"), UInt8(ascii: "}"):
            character(byte)
        default:
            break
        }
    }

    private mutating func controlWord() {
        let start = index
        while index < bytes.count, isLetter(bytes[index]) { index += 1 }
        let word = String(decoding: bytes[start..<index], as: UTF8.self)

        var parameter: Int?
        let parameterStart = index
        if index < bytes.count, bytes[index] == UInt8(ascii: "-") { index += 1 }
        while index < bytes.count, bytes[index] >= UInt8(ascii: "0"), bytes[index] <= UInt8(ascii: "9") { index += 1 }
        if index > parameterStart {
            parameter = Int(String(decoding: bytes[parameterStart..<index], as: UTF8.self))
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: " ") { index += 1 }

        if Self.skippedDestinations.contains(word) { state.skipped = true }
        switch word {
        case "b": state.bold = parameter != 0
        case "i": state.italic = parameter != 0
        case "fs": state.halfPoints = parameter ?? 24
        case "plain":
            state.bold = false
            state.italic = false
            state.halfPoints = 24
        case "pard": state.centered = false
        case "qc": state.centered = true
        case "ql", "qr", "qj": state.centered = false
        case "par", "line", "sect", "page": emit("\n")
        case "tab": emit("\t")
        case "emdash": emit("\u{2014}")
        case "endash": emit("\u{2013}")
        case "lquote": emit("\u{2018}")
        case "rquote": emit("\u{2019}")
        case "ldblquote": emit("\u{201C}")
        case "rdblquote": emit("\u{201D}")
        case "bullet": emit("\u{2022}")
        case "ansicpg": codepage = parameter ?? 1252
        case "uc": state.unicodeSkip = max(0, parameter ?? 1)
        case "u":
            guard let parameter else { break }
            unicode(UInt16(truncatingIfNeeded: parameter < 0 ? parameter + 65_536 : parameter))
            pendingSkip = state.unicodeSkip
        case "bin":
            index = min(bytes.count, index + max(0, parameter ?? 0))
        default: break
        }
    }

    private func isLetter(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
    }

    private mutating func character(_ byte: UInt8) {
        if pendingSkip > 0 {
            pendingSkip -= 1
            return
        }
        if codepage == 1252, (0x80...0x9F).contains(byte) {
            emit(String(UnicodeScalar(Self.cp1252[Int(byte) - 0x80])!))
        } else {
            // Latin-1 matches cp1252 from 0xA0 up; other codepages are rare on FA.
            emit(String(UnicodeScalar(byte)))
        }
    }

    private mutating func unicode(_ unit: UInt16) {
        if UTF16.isLeadSurrogate(unit) {
            highSurrogate = unit
            return
        }
        let units = highSurrogate.map { [$0, unit] } ?? [unit]
        highSurrogate = nil
        emit(String(decoding: units, as: UTF16.self))
    }

    private mutating func emit(_ text: String) {
        guard !state.skipped else { return }
        let font = StoryFont(size: CGFloat(state.halfPoints) / 2, bold: state.bold, italic: state.italic)
        if font != runFont || state.centered != runCentered {
            flush()
            runFont = font
            runCentered = state.centered
        }
        run += text
    }

    private mutating func flush() {
        guard !run.isEmpty else { return }
        var attributes: [NSAttributedString.Key: Any] = [.storyFont: runFont]
        if runCentered { attributes[.storyCentered] = true }
        result.append(NSAttributedString(string: run, attributes: attributes))
        run = ""
    }

    private static let cp1252: [UInt32] = [
        0x20AC, 0xFFFD, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
        0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0xFFFD, 0x017D, 0xFFFD,
        0xFFFD, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
        0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0xFFFD, 0x017E, 0x0178,
    ]
}
