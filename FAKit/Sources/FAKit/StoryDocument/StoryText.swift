//
//  StoryText.swift
//  FAKit
//
//  Created by Ceylo on 25/09/2026.
//

import Foundation

/// The plain-text story formats, which need no platform framework to read.
enum StoryText {
    /// The text of a txt/md story, or `nil` for any other format or for data that isn't UTF-8.
    static func text(from data: Data, filename: String) -> String? {
        switch (filename as NSString).pathExtension.lowercased() {
        case "txt", "text", "md":
            return String(data: data, encoding: .utf8)?.replacingOccurrences(of: "\r\n", with: "\n")
        default:
            return nil
        }
    }
}
