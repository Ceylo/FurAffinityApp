//
//  FANote.swift
//  
//
//  Created by Ceylo on 11/04/2022.
//

import Foundation
import FAPages

public struct FANote: Equatable {
    public let author: String
    public let displayAuthor: String
    public let title: String
    public let datetime: String
    public let naturalDatetime: String
    public let htmlMessage: String
    public let answerKey: String
    
    public init(author: String, displayAuthor: String, title: String, datetime: String,
                naturalDatetime: String, htmlMessage: String, answerKey: String) {
        self.author = author
        self.displayAuthor = displayAuthor
        self.title = title
        self.datetime = datetime
        self.naturalDatetime = naturalDatetime
        self.htmlMessage = htmlMessage.selfContainedFAHtmlSubmission
        self.answerKey = answerKey
    }
}

public extension FANote {
    init(_ notePage: FANotePage) {
        self.init(author: notePage.author, displayAuthor: notePage.displayAuthor,
                  title: notePage.title, datetime: notePage.datetime, naturalDatetime: notePage.naturalDatetime,
                  htmlMessage: notePage.htmlMessage, answerKey: notePage.answerKey)
    }
}
