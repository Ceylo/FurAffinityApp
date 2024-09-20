//
//  FAJournal.swift
//  
//
//  Created by Ceylo on 21/11/2021.
//

import Foundation
import FAPages

public struct FAJournal: Equatable, Sendable {
    public let url: URL
    public let author: String
    public let displayAuthor: String
    public let title: String
    public let datetime: String
    public let naturalDatetime: String
    public let description: AttributedString
    public let comments: [FAComment]
    
    public init(url: URL, author: String,
                displayAuthor: String,
                title: String,
                datetime: String,
                naturalDatetime: String,
                description: AttributedString,
                comments: [FAComment]) {
        self.url = url
        self.author = author
        self.displayAuthor = displayAuthor
        self.title = title
        self.datetime = datetime
        self.naturalDatetime = naturalDatetime
        self.description = description //.selfContainedFAHtmlSubmission
        self.comments = comments
    }
}

extension FAJournal {
    public init(_ page: FAJournalPage, url: URL) async throws {
        try self.init(
            url: url,
            author: page.author,
            displayAuthor: page.displayAuthor,
            title: page.title,
            datetime: page.datetime,
            naturalDatetime: page.naturalDatetime,
            description: await AttributedString(FAHTML: page.htmlDescription.selfContainedFAHtmlSubmission),
            comments: await FAComment.buildCommentsTree(page.comments)
        )
    }
}
