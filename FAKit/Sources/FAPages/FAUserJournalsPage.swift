//
//  FAUserJournalsPage.swift
//  FAKit
//
//  Created by Ceylo on 11/10/2024.
//

import Foundation
import SwiftSoup

public struct FAUserJournalsPage: Equatable, Sendable {
    public struct Journal: Equatable, Sendable, Identifiable {
        public let id: Int
        public let title: String
        public let datetime: String
        public let naturalDatetime: String
        public let url: URL
        
        public init(id: Int, title: String, datetime: String, naturalDatetime: String, url: URL) {
            self.id = id
            self.title = title
            self.datetime = datetime
            self.naturalDatetime = naturalDatetime
            self.url = url
        }
    }
    
    public let displayAuthor: String
    public let journals: [Journal]
}

extension FAUserJournalsPage {
    public init?(data: Data) {
        let state = signposter.beginInterval("All Journals Preview Parsing")
        defer { signposter.endInterval("All Journals Preview Parsing", state) }
        
        do {
            let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
            let authorQuery = "#site-content > userpage-nav-header > userpage-nav-user-details username > div.c-usernameBlock > a.c-usernameBlock__displayName"
            let displayAuthor = try doc.select(authorQuery).text()
            
            let journalsQuery = "html body#pageid-journals-list div#main-window div#site-content div#columnpage div.content section"
            let journalNodes = try doc.select(journalsQuery)
            let journals = try journalNodes.map(Self.decodeJournal)
            
            self.init(displayAuthor: displayAuthor, journals: journals)
        } catch {
            logger.error("Decoding failure in \(#file, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }
    
    private static func decodeJournal(_ node: SwiftSoup.Element) throws -> Journal {
        let idStr = try node
            .attr("id")
            .substring(matching: #"jid:(\d+)"#)
            .unwrap()
        let id = try Int(idStr).unwrap()
        
        let title = try node.select("div.section-header > h2").text()
        let dateNode = try node.select("div.section-header > span > strong > span.popup_date")
        let datetime = try dateNode.attr("title")
        let naturalDatetime = try dateNode.text()
        let url = FAURLs.journalUrl(jid: id)
        
        return .init(
            id: id,
            title: title,
            datetime: datetime,
            naturalDatetime: naturalDatetime,
            url: url
        )
    }
}
