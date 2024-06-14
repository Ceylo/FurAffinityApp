//
//  FANotePage.swift
//  
//
//  Created by Ceylo on 09/04/2022.
//

import Foundation
import SwiftSoup

public struct FANotePage: Equatable {
    public let author: String
    public let displayAuthor: String
    public let title: String
    public let datetime: String
    public let naturalDatetime: String
    public let htmlMessage: String
    public let answerKey: String
}

extension FANotePage {
    public init?(data: Data) {
        let state = signposter.beginInterval("Note Parsing")
        defer { signposter.endInterval("Note Parsing", state) }
        
        do {
            let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))

            let noteContainerQuery = "section#message"
            let noteContainerNode = try doc.select(noteContainerQuery)
            
            self.title = try noteContainerNode.select("div.section-header h2").text()
            
            let authorQuery = "div.section-header div.message-center-note-information div.addresses a"
            let authorNodes = try noteContainerNode.select(authorQuery)
            if authorNodes.count == 2 {
                guard let authorNode = authorNodes.first(),
                      let author = try authorNode.attr("href").substring(matching: "/user/(.+)/")
                else { return nil }
                self.author = author
                self.displayAuthor = try authorNode.select("strong").text()
            } else {
                let deletedQuery = "div.section-header div.message-center-note-information.addresses span.user-name-deleted"
                let deletedNode = try noteContainerNode.select(deletedQuery)
                if try deletedNode.text() == "[deleted]" {
                    self.author = ""
                    self.displayAuthor = "[deleted user]"
                } else {
                    return nil
                }
            }
            
            self.htmlMessage = try noteContainerNode
                .select("div.section-body > div.user-submitted-links")
                .html()
            let dateNode = try noteContainerNode
                .select("div.section-header div.message-center-note-information div.addresses span.popup_date")
            self.datetime = try dateNode.attr("title")
            self.naturalDatetime = try dateNode.text()
            
            let keyNode = try doc.select("form#note-form input[name=\"key\"]")
            self.answerKey = try keyNode.attr("value")
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            return nil
        }
    }
}
