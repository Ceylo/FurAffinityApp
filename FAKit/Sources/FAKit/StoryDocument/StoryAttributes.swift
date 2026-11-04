//
//  StoryAttributes.swift
//  FAKit
//
//  Created by Ceylo on 04/11/2026.
//

import Foundation

public struct StoryFont: Hashable, Sendable {
    public var size: CGFloat
    public var bold: Bool
    public var italic: Bool
    public var name: String?

    public init(size: CGFloat, bold: Bool = false, italic: Bool = false, name: String? = nil) {
        self.size = size
        self.bold = bold
        self.italic = italic
        self.name = name
    }
}

extension NSAttributedString.Key {
    static let storyFont = NSAttributedString.Key("FAStoryFont")
    static let storyCentered = NSAttributedString.Key("FAStoryCentered")
    static let storyImage = NSAttributedString.Key("FAStoryImage")
}

public struct StoryRun: Hashable, Sendable {
    public var text: String
    public var font: StoryFont
}

public struct StoryParagraph: Hashable, Sendable {
    public var runs: [StoryRun]
    public var centered: Bool
    public var image: Data?

    public var text: String { runs.map(\.text).joined() }
}

extension StoryParagraph {
    static func paragraphs(from text: NSAttributedString, bodyPointSize: CGFloat) -> [StoryParagraph] {
        let string = text.string as NSString
        var paragraphs: [StoryParagraph] = []
        var start = 0
        func flush(end: Int) {
            var paragraph = StoryParagraph(runs: [], centered: false, image: nil)
            let range = NSRange(location: start, length: end - start)
            if range.length > 0 {
                text.enumerateAttributes(in: range) { attributes, runRange, _ in
                    if let image = attributes[.storyImage] as? Data {
                        paragraph.image = image
                        return
                    }
                    if attributes[.storyCentered] as? Bool == true { paragraph.centered = true }
                    let font = attributes[.storyFont] as? StoryFont ?? StoryFont(size: bodyPointSize)
                    let runText = string.substring(with: runRange)
                    if let last = paragraph.runs.last, last.font == font {
                        paragraph.runs[paragraph.runs.count - 1].text += runText
                    } else {
                        paragraph.runs.append(StoryRun(text: runText, font: font))
                    }
                }
            }
            if paragraph.image != nil { paragraph.runs = [] }
            paragraphs.append(paragraph)
            start = end + 1
        }
        for i in 0..<string.length where string.character(at: i) == 0x0A {
            flush(end: i)
        }
        flush(end: string.length)
        return paragraphs
    }
}

extension Array where Element == StoryParagraph {
    public var dominantFontSize: CGFloat? {
        var lengthBySize: [CGFloat: Int] = [:]
        for run in lazy.flatMap(\.runs) {
            lengthBySize[run.font.size, default: 0] += run.text.utf16.count
        }
        return lengthBySize.max { $0.value < $1.value }?.key
    }
}
