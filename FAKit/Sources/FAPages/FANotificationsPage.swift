//
//  FANotificationsPage.swift
//  
//
//  Created by Ceylo on 07/04/2022.
//

import Foundation
import SwiftSoup

public struct FANotificationsPage: Equatable {
    public struct JournalHeader: Equatable {
        public let id: Int
        public let author: String
        public let displayAuthor: String
        public let title: String
        public let datetime: String
        public let naturalDatetime: String
        public let journalUrl: URL
    }
    
    public enum Header: Equatable {
        case journal(JournalHeader)
    }
    
    public static let url = URL(string: "https://www.furaffinity.net/msg/others/")!
    public let headers: [Header]
}

extension FANotificationsPage {
    public init?(data: Data) async {
        let state = signposter.beginInterval("All Notifications Preview Parsing")
        defer { signposter.endInterval("All Notifications Preview Parsing", state) }
        
        do {
            let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
            
            let journalsQuery = "body div#main-window div#site-content div#messagecenter-other div#columnpage div.submission-content form#messages-form section#messages-journals ul.message-stream li div.table"
            let journalNodes = try doc.select(journalsQuery)
            
            self.headers = try await journalNodes
                .parallelMap { try JournalHeader($0) }
                .map { .journal($0) }
        } catch {
            logger.error("Decoding failure in \(#file, privacy: .public): \(error, privacy: .public)")
            return nil
        }
            
    }
}

extension FANotificationsPage.JournalHeader {
    init(_ node: SwiftSoup.Element) throws {
        let state = signposter.beginInterval("Journal Preview Parsing")
        defer { signposter.endInterval("Journal Preview Parsing", state) }
        
        let baseNode = try node.select("div.user-submitted-links")
        let urlStr = try baseNode.select("a").first().unwrap().attr("href")
        let url = try URL(unsafeString: FAHomePage.url.absoluteString + urlStr)
        
        let id = try Int(urlStr.substring(matching: "/journal/(\\d+)/").unwrap()).unwrap()
        let title = try baseNode.select("a strong.journal_subject").text()
        
        let authorNode = try node.select("a").dropFirst().first.unwrap()
        let author = try authorNode.attr("href")
            .substring(matching: "/user/(.+)/")
            .unwrap()
        let displayAuthor = try authorNode.text()
        
        let datetimeNode = try node.select("span span.popup_date")
        let datetime = try datetimeNode.attr("title")
        let naturalDatetime = try datetimeNode.text()
        
        self.init(id: id, author: author, displayAuthor: displayAuthor, title: title, datetime: datetime, naturalDatetime: naturalDatetime, journalUrl: url)
    }
}
