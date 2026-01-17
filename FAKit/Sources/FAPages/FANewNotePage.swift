//
//  FANewNotePage.swift
//  FAKit
//
//  Created by Ceylo on 21/06/2025.
//

import Foundation
import SwiftSoup

public struct FANewNotePage: FAPage {
    public let apiKey: String
}

extension FANewNotePage {
    public init(data: Data, url: URL) throws {
        let state = signposter.beginInterval("New Note Parsing")
        defer { signposter.endInterval("New Note Parsing", state) }
        
        do {
            let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
            
            let apiKeyQuery = "html body div#main-window div#site-content form#note-form > input[name=\"key\"]"
            let apiKeyNode = try doc.select(apiKeyQuery)
            self.apiKey = try apiKeyNode.attr("value")
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            throw error
        }
    }
}
