//
//  FASystemMessagePage.swift
//  FAKit
//
//  Created by Ceylo on 21/06/2025.
//

import Foundation
import SwiftSoup

public struct FASystemMessagePage: Equatable {
    public let message: String
}

extension FASystemMessagePage {
    public init(data: Data) throws {
        let state = signposter.beginInterval("FA System Message parsing")
        defer { signposter.endInterval("FA System Message parsing", state) }
        
        do {
            let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
            //set pretty print to false, so \n is not removed
            doc.outputSettings(OutputSettings().prettyPrint(pretty: false))
            
            let sectionBodyQuery = "html > body > div#main-window > div#site-content > div#standardpage > section.notice-message > div.section-body"
            let sectionBodyNode = try doc.select(sectionBodyQuery)
            
            let title = try sectionBodyNode.select("h2").text()
            guard title == "System Message" else {
                throw FAPagesError.parserFailureError()
            }
            
            var messageNode = try sectionBodyNode.select("div.redirect-message")
            try messageNode.select("a.button")
                .remove()
            if messageNode.isEmpty() {
                messageNode = try sectionBodyNode.select("div.section-body p.link-override")
            }
            if messageNode.isEmpty() {
                throw FAPagesError.parserFailureError()
            }
            
            self.message = try messageNode
                .textWithNewLines()
                .replacingOccurrences(of: "\n\n\n\n", with: "\n\n")
                .replacingOccurrences(of: "\n\n\n", with: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            throw error
        }
    }
}
