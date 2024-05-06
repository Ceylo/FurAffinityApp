//
//  FAJournal.swift
//  
//
//  Created by Ceylo on 21/11/2021.
//

import Foundation
import FAPages

public struct FAJournal: Equatable {
    public let url: URL
    public let author: String
    public let displayAuthor: String
    public let authorAvatarUrl: URL
    public let title: String
    public let datetime: String
    public let naturalDatetime: String
    public let htmlDescription: String
    public let comments: [FAComment]
    
    public init(url: URL, author: String,
                displayAuthor: String, authorAvatarUrl: URL,
                title: String,
                datetime: String,
                naturalDatetime: String,
                htmlDescription: String,
                comments: [FAComment]) {
        self.url = url
        self.author = author
        self.displayAuthor = displayAuthor
        self.authorAvatarUrl = authorAvatarUrl
        self.title = title
        self.datetime = datetime
        self.naturalDatetime = naturalDatetime
        self.htmlDescription = htmlDescription.selfContainedFAHtmlSubmission
        self.comments = comments
    }
}

extension FAJournal {
    public init(_ page: FAJournalPage, url: URL) throws {
        try self.init(url: url,
                  author: page.author,
                  displayAuthor: page.displayAuthor,
                  authorAvatarUrl: page.authorAvatarUrl,
                  title: page.title,
                  datetime: page.datetime,
                  naturalDatetime: page.naturalDatetime,
                  htmlDescription: page.htmlDescription,
                  comments: FAComment.buildCommentsTree(page.comments))
    }
}
