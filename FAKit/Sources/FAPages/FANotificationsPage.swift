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
            let journalNodes = try notificationsNode.select("section#messages-journals ul.message-stream li div.table")

            async let submissionCommentHeaders = submissionCommentNodes
                .parallelMap { node in
                    do {
                        return try Header.submissionComment(node)
                    } catch {
                        let html = (try? node.html()) ?? ""
                        logger.error("Failed decoding comment header. Error: \(error). Generated while parsing: \(html)")
                        return nil
                    }
                }
                .compactMap { $0 }
            
            async let journalCommentHeaders = journalCommentNodes
                .parallelMap { node in
                    do {
                        return try Header.journalComment(node)
                    } catch {
                        let html = (try? node.html()) ?? ""
                        logger.error("Failed decoding comment header. Error: \(error). Generated while parsing: \(html)")
                        return nil
                    }
                }
                .compactMap { $0 }
            
            async let journalHeaders = journalNodes
                .parallelMap { node in
                    do {
                        return try Header.journal(node)
                    } catch {
                        let html = (try? node.html()) ?? ""
                        logger.error("Failed decoding journal header. Error: \(error). Generated while parsing: \(html)")
                        return nil
                    }
                }
                .compactMap { $0 }
            
            self.submissionCommentHeaders = await submissionCommentHeaders
            self.journalCommentHeaders = await journalCommentHeaders
            self.journalHeaders = await journalHeaders
        } catch {
            logger.error("Decoding failure in \(#file, privacy: .public): \(error, privacy: .public)")
            return nil
        }
            
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
        let title = try baseNode.select("a strong.journal_subject").text()
        
        let authorNode = try node.select("a").dropFirst().first.unwrap()
        let author = try authorNode.attr("href")
            .substring(matching: "/user/(.+)/")
            .unwrap()
        let displayAuthor = try authorNode.text()
        
        let datetimeNode = try node.select("span span.popup_date")
        let datetime = try datetimeNode.attr("title")
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
        let datetime = try datetimeNode.attr("title")
        let naturalDatetime = try datetimeNode.text()
        
        let authorNode = try node.select("> a")
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
}
