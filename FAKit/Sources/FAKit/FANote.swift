//
//  FANote.swift
//  
//
//  Created by Ceylo on 11/04/2022.
//

import Foundation
import FAPages

public struct FANote: Equatable, Sendable {
    public let url: URL
    public let author: String
    public let displayAuthor: String
    public let title: String
    public let datetime: String
    public let naturalDatetime: String
    public let message: AttributedString
    public let answerKey: String
    
    public init(url: URL, author: String, displayAuthor: String, title: String, datetime: String,
                naturalDatetime: String, message: AttributedString, answerKey: String) {
        self.url = url
        self.author = author
        self.displayAuthor = displayAuthor
        self.title = title
        self.datetime = datetime
        self.naturalDatetime = naturalDatetime
        self.message = message
        self.answerKey = answerKey
    }
}

public extension FANote {
    init(_ notePage: FANotePage, url: URL) async throws {
        try self.init(
            url: url, author: notePage.author, displayAuthor: notePage.displayAuthor,
            title: notePage.title, datetime: notePage.datetime, naturalDatetime: notePage.naturalDatetime,
            message: await AttributedString(FAHTML: notePage.htmlMessage.selfContainedFAHtmlSubmission), answerKey: notePage.answerKey
        )
    }
}
