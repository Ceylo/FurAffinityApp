//
//  FANotificationsPage.swift
//  
//
//  Created by Ceylo on 07/04/2022.
//

import Foundation
import SwiftSoup

public struct FANotificationsPage: Equatable {
    public struct SubmissionCommentHeader: Equatable {
        public let cid: Int
        public let author: String
        public let displayAuthor: String
        public let submissionTitle: String
        public let datetime: String
        public let naturalDatetime: String
        public let submissionUrl: URL
    }
    
    public struct JournalHeader: Equatable {
        public let id: Int
        public let author: String
        public let displayAuthor: String
        public let title: String
        public let datetime: String
        public let naturalDatetime: String
        public let journalUrl: URL
    }
    
    public let submissionCommentHeaders: [SubmissionCommentHeader]
    public let journalHeaders: [JournalHeader]
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
            let journalNodes = try notificationsNode.select("section#messages-journals ul.message-stream li div.table")

            async let submissionCommentHeaders = submissionCommentNodes
                .parallelMap { try SubmissionCommentHeader($0) }
            
            async let journalHeaders = journalNodes
                .parallelMap { try JournalHeader($0) }
            
            self.submissionCommentHeaders = try await submissionCommentHeaders
            self.journalHeaders = try await journalHeaders
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
        
        self.init(id: id, author: author, displayAuthor: displayAuthor, title: title, datetime: datetime, naturalDatetime: naturalDatetime, journalUrl: url)
    }
}

extension FANotificationsPage.SubmissionCommentHeader {
    init(_ node: SwiftSoup.Element) throws {
        let state = signposter.beginInterval("Submission Comment Preview Parsing")
        defer { signposter.endInterval("Submission Comment Preview Parsing", state) }
        
        let datetimeNode = try node.select("div span.popup_date")
        let datetime = try datetimeNode.attr("title")
        let naturalDatetime = try datetimeNode.text()
        
        let authorNode = try node.select("> a")
        let author = try authorNode.attr("href")
            .substring(matching: "/user/(.+)/")
            .unwrap()
        let displayAuthor = try authorNode.text()
        
        let commentTargetNode = try node.select("strong i a")
        let title = try commentTargetNode.text()
        let urlStr = try commentTargetNode.attr("href")
        let cid = try Int(urlStr.substring(matching: "/view/\\d+/#cid:(\\d+)").unwrap()).unwrap()
        let url = try URL(unsafeString: FAURLs.homeUrl.absoluteString + urlStr)
        
        self.init(cid: cid, author: author, displayAuthor: displayAuthor, submissionTitle: title, datetime: datetime, naturalDatetime: naturalDatetime, submissionUrl: url)
    }
}
