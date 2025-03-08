//
//  FANotificationsPage.swift
//  
//
//  Created by Ceylo on 07/04/2022.
//

import Foundation
@preconcurrency import SwiftSoup

public struct FANotificationsPage: Equatable, Sendable {
    public struct Header: Equatable, Sendable {
        public let id: Int
        public let author: String
        public let displayAuthor: String
        public let title: String
        public let datetime: String
        public let naturalDatetime: String
        public let url: URL
    }
    
    public let submissionCommentHeaders: [Header]
    public let journalCommentHeaders: [Header]
    public let shoutHeaders: [Header]
    public let journalHeaders: [Header]
}

extension FANotificationsPage {
    public init?(data: Data) async {
        let state = signposter.beginInterval("All Notifications Preview Parsing")
        defer { signposter.endInterval("All Notifications Preview Parsing", state) }
        
        do {
            let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
            
            let notificationsQuery = "body div#main-window div#site-content div#messagecenter-other div#columnpage div.submission-content form#messages-form"
            let notificationsNode = try doc.select(notificationsQuery)
            let submissionCommentNodes = try notificationsNode.select("section#messages-comments-submission div.section-body ul.message-stream li")
            let journalCommentNodes = try notificationsNode.select("section#messages-comments-journal div.section-body ul.message-stream li")
            let shoutNodes = try notificationsNode.select("section#messages-shouts > div.section-body > ul.message-stream > li")
            let journalNodes = try notificationsNode.select("section#messages-journals ul.message-stream li div.table")

            async let submissionCommentHeaders = Self.decodeNodes(submissionCommentNodes, Header.submissionComment)
            async let journalCommentHeaders = Self.decodeNodes(journalCommentNodes, Header.journalComment)
            async let shoutHeaders = Self.decodeNodes(shoutNodes, { try Header.shout($0, page: doc) })
            async let journalHeaders = Self.decodeNodes(journalNodes, Header.journal)
            
            self.submissionCommentHeaders = await submissionCommentHeaders
            self.journalCommentHeaders = await journalCommentHeaders
            self.shoutHeaders = await shoutHeaders
            self.journalHeaders = await journalHeaders
        } catch {
            logger.error("Decoding failure in \(#file, privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }
    
    static private func decodeNodes<T: Sendable>(_ nodes: SwiftSoup.Elements, _ headerDecoder: @escaping @Sendable (SwiftSoup.Element) throws -> T) async -> [T] {
        await nodes.parallelMap { node in
            do {
                return try headerDecoder(node)
            } catch {
                let html = (try? node.html()) ?? ""
                logger.error("Failed decoding header for \(T.self, privacy: .public). Error: \(error, privacy: .public). Generated while parsing: \(html, privacy: .public)")
                return nil
            }
        }
        .compactMap { $0 }
    }
}

extension FANotificationsPage.Header {
    static func journal(_ node: SwiftSoup.Element) throws -> Self {
        let state = signposter.beginInterval("Journal Preview Parsing")
        defer { signposter.endInterval("Journal Preview Parsing", state) }
        
        let baseNode = try node.select("div.user-submitted-links")
        let urlStr = try baseNode.select("a").first().unwrap().attr("href")
        let url = try URL(unsafeString: FAURLs.homeUrl.absoluteString + urlStr)
        
        let id = try Int(urlStr.substring(matching: "/journal/(\\d+)/").unwrap()).unwrap()
        let title = try baseNode.select("em.journal_subject").text()
        
        let authorNode = try node.select("span.c-usernameBlockSimple a")
        let author = try authorNode.attr("href")
            .substring(matching: "/user/(.+)/")
            .unwrap()
        
        let displayAuthor = try authorNode.select("span.c-usernameBlockSimple__displayName").text()
        
        let datetimeNode = try node.select("span span.popup_date")
        let datetime = try String(datetimeNode.attr("title").trimmingPrefix("on "))
        let naturalDatetime = try datetimeNode.text()
        
        return .init(id: id, author: author, displayAuthor: displayAuthor, title: title, datetime: datetime, naturalDatetime: naturalDatetime, url: url)
    }
    
    static func submissionComment(_ node: SwiftSoup.Element) throws -> Self {
        try signposter.withIntervalSignpost("Submission Comment Preview Parsing") {
            try comment(node, urlNodeSelector: "strong i a", idMatchingPattern: "/view/\\d+/#cid:(\\d+)")
        }
    }
    
    static func journalComment(_ node: SwiftSoup.Element) throws -> Self {
        try signposter.withIntervalSignpost("Journal Comment Preview Parsing") {
            try comment(node, urlNodeSelector: "b i a", idMatchingPattern: "/journal/\\d+/#cid:(\\d+)")
        }
    }
    
    static private func comment(_ node: SwiftSoup.Element, urlNodeSelector: String, idMatchingPattern: String) throws -> Self {
        let datetimeNode = try node.select("div span.popup_date")
        let datetime = try String(datetimeNode.attr("title").trimmingPrefix("on "))
        let naturalDatetime = try datetimeNode.text()
        
        let authorNode = try node.select("span.c-usernameBlockSimple a")
        let author = try authorNode.attr("href")
            .substring(matching: "/user/(.+)/")
            .unwrap()
        let displayAuthor = try authorNode.text()
        
        let commentTargetNode = try node.select(urlNodeSelector)
        let title = try commentTargetNode.text()
        let urlStr = try commentTargetNode.attr("href")
        let id = try Int(urlStr.substring(matching: idMatchingPattern).unwrap()).unwrap()
        let url = try URL(unsafeString: FAURLs.homeUrl.absoluteString + urlStr)
        
        return .init(id: id, author: author, displayAuthor: displayAuthor, title: title, datetime: datetime, naturalDatetime: naturalDatetime, url: url)
    }
    
    static func shout(_ node: SwiftSoup.Element, page: SwiftSoup.Element) throws -> Self {
        let state = signposter.beginInterval("Shout Preview Parsing")
        defer { signposter.endInterval("Shout Preview Parsing", state) }
        
        let linkNode = try node.select("a").last().unwrap()
        let userStr = try linkNode.attr("href")
        let author = try userStr.substring(matching: "/user/(.+)/").unwrap()
        let displayAuthor = try linkNode.text()
        
        let id = try Int(node.select("input").attr("value")).unwrap()
        let currentUserAvatarNode = try page.select("nav#ddmenu > ul > li > div > a > img.avatar").first().unwrap()
        let currentUserUrlStr = try currentUserAvatarNode.parent().unwrap().attr("href")
        let commentAnchor = "#shout-\(id)"
        let url = try URL(unsafeString: FAURLs.homeUrl.absoluteString + currentUserUrlStr + commentAnchor)
        let title = ""
        
        let datetimeNode = try node.select("div span.popup_date")
        let datetime = try datetimeNode.attr("title")
        let naturalDatetime = try datetimeNode.text()
        
        return .init(id: id, author: author, displayAuthor: displayAuthor, title: title, datetime: datetime, naturalDatetime: naturalDatetime, url: url)
    }
}
