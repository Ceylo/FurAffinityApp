//
//  StoryText.swift
//  FAKit
//
//  Created by Ceylo on 25/09/2026.
//

import Foundation

/// The plain-text story formats, which need no platform framework to read. `StoryDocument`
/// builds its rich text for them from here on iOS; Android renders the lines directly.
public enum StoryText {
    /// The text of a txt/md story, or `nil` for any other format or for data that isn't UTF-8.
    public static func text(from data: Data, filename: String) -> String? {
        switch (filename as NSString).pathExtension.lowercased() {
        case "txt", "text", "md":
            return String(data: data, encoding: .utf8)
        default:
            return nil
        }
    }

    /// ``text(from:filename:)`` split into its lines, one per paragraph; a blank line is an
    /// empty string. `\r\n` counts as one line break.
    public static func paragraphs(from data: Data, filename: String) -> [String]? {
        text(from: data, filename: filename).map { text in
            text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        }
    }
}
