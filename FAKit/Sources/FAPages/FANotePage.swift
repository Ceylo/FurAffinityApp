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
    public let htmlMessage: String
}

extension FANotePage {
    public init?(data: Data) {
        do {
            let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))

            let noteContainerQuery = "section#message"
            let noteContainerNode = try doc.select(noteContainerQuery)
            
            self.title = try noteContainerNode.select("div.section-header h2").text()
            
            let authorQuery = "div.section-header div.message-center-note-information div.addresses a"
            guard let authorNode = try noteContainerNode.select(authorQuery).first(),
                  let author = try authorNode.attr("href").substring(matching: "/user/(.+)/")
            else { return nil }
            
            self.author = author
            self.displayAuthor = try authorNode.select("strong").text()
            self.htmlMessage = try noteContainerNode.select("div.section-body div.user-submitted-links").html()
            self.datetime = try noteContainerNode.select("div.section-header div.message-center-note-information div.addresses span.popup_date").attr("title")

        } catch {
            print(error)
            return nil
        }
    }
}
