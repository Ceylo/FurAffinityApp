//
//  FASystemErrorPage.swift
//  FAKit
//
//  Created by Ceylo on 21/06/2025.
//

import Foundation
import SwiftSoup

public struct FASystemErrorPage: Equatable {
    public let message: String
}

extension FASystemErrorPage {
    public init(data: Data) throws {
        let state = signposter.beginInterval("FA System Error parsing")
        defer { signposter.endInterval("FA System Error parsing", state) }
        
        do {
            let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
            //set pretty print to false, so \n is not removed
            doc.outputSettings(OutputSettings().prettyPrint(pretty: false))
            
            let titleQuery = "html > body > section > div.section-header"
            let messageQuery = "html > body > section > div.section-body"
            let title = try doc.select(titleQuery).text()
            guard title == "System Error" else {
                throw FAPagesError.parserFailureError()
            }
            
            let messageNode = try doc.select(messageQuery)
            try messageNode.select("a.button")
                .remove()
            self.message = try messageNode
                .textWithNewLines()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            throw error
        }
    }
}

extension Elements {
    // Based on https://github.com/scinfu/SwiftSoup/issues/156#issuecomment-943009494
    func textWithNewLines() throws -> String {
        //select all <br> tags and append \n after that
        try select("br").after("\n")
                        
        //get the HTML from the document, and retaining original new lines
        let str = try html()
                
        let strWithNewLines = try SwiftSoup.clean(str, "", Whitelist.none(), OutputSettings().prettyPrint(pretty: false))
        return try strWithNewLines.unwrap()
    }
}
