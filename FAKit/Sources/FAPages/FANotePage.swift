//
//  FANotePage.swift
//  
//
//  Created by Ceylo on 09/04/2022.
//

import Foundation
import SwiftSoup

public struct FANotePage: Equatable, Sendable {
    public let author: String
    public let displayAuthor: String
    public let title: String
    public let datetime: String
    public let naturalDatetime: String
    public let htmlMessage: String
    public let htmlMessageWithoutWarning: String
    public let answerKey: String
    public let answerPlaceholderMessage: String
}

extension FANotePage {
    public init(data: Data) throws {
        let state = signposter.beginInterval("Note Parsing")
        defer { signposter.endInterval("Note Parsing", state) }
        
        do {
            let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))

            let noteContainerQuery = "section#message"
            let noteContainerNode = try doc.select(noteContainerQuery)
            
            self.title = try noteContainerNode.select("div.section-header h2").text()
            
            let authorQuery = "div.section-header div.message-center-note-information div.addresses div.c-usernameBlock a.c-usernameBlock__displayName"
            let authorNodes = try noteContainerNode.select(authorQuery)
            if authorNodes.count == 2 {
                let authorNode = try authorNodes.first().unwrap()
                let author = try authorNode
                    .attr("href")
                    .substring(matching: "/user/(.+)/")
                    .unwrap()
                self.author = author
                self.displayAuthor = try authorNode.text()
            } else {
                let deletedQuery = "div.section-header div.message-center-note-information.addresses span.user-name-deleted"
                let deletedNode = try noteContainerNode.select(deletedQuery)
                if try deletedNode.text() == "[deleted]" {
                    self.author = ""
                    self.displayAuthor = "[deleted user]"
                } else {
                    throw FAPagesError.parserFailureError()
                }
            }
            
            let noteMessageNode = try noteContainerNode
                .select("div.section-body > div.user-submitted-links")
            try noteMessageNode
                .select("div.noteWarningMessage")
                .wrap("<i class=\"fa-app-warning\" style=\"color: red;\"></i>")
                .append("<br />")
            self.htmlMessage = try noteMessageNode.html()
            let warningNode = try noteMessageNode.select("i.fa-app-warning")
            if !warningNode.isEmpty(){
                try warningNode.remove()
                self.htmlMessageWithoutWarning = try noteMessageNode.html()
            } else {
                self.htmlMessageWithoutWarning = self.htmlMessage
            }
            
            let dateNode = try noteContainerNode
                .select("div.section-header div.message-center-note-information div.addresses span.popup_date")
            self.datetime = try dateNode.attr("title")
            self.naturalDatetime = try dateNode.text()
            
            let keyNode = try doc.select("form#note-form input[name=\"key\"]")
            self.answerKey = try keyNode.attr("value")
            
            let placeholderMessageNodeQuery = "div#main-window div#site-content div.messagecenter-mail-container div.messagecenter-mail-content-pane div.messagecenter-mail-note-preview-pane form#note-form section div.section-body div.table div.table-cell.user-submitted-links textarea#JSMessage_reply"
            let placeholderMessageNode = try doc.select(placeholderMessageNodeQuery)
            self.answerPlaceholderMessage = try "\n\n" + placeholderMessageNode.text()
                .replacingOccurrences(of: "\r\n", with: "\n")
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            throw error
        }
    }
}
