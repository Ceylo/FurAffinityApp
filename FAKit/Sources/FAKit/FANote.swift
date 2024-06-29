//
//  FANote.swift
//  
//
//  Created by Ceylo on 11/04/2022.
//

import Foundation
import FAPages

public struct FANote: Equatable, Sendable {
    public let author: String
    public let displayAuthor: String
    public let title: String
    public let datetime: String
    public let naturalDatetime: String
    public let message: AttributedString
    public let answerKey: String
    
    public init(author: String, displayAuthor: String, title: String, datetime: String,
                naturalDatetime: String, message: AttributedString, answerKey: String) {
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
    init(_ notePage: FANotePage) throws {
        try self.init(
            author: notePage.author, displayAuthor: notePage.displayAuthor,
            title: notePage.title, datetime: notePage.datetime, naturalDatetime: notePage.naturalDatetime,
            message: AttributedString(FAHTML: notePage.htmlMessage.selfContainedFAHtmlSubmission), answerKey: notePage.answerKey
        )
    }
}
