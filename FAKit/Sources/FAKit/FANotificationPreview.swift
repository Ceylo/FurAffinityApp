//
//  FANotePreview.swift
//  
//
//  Created by Ceylo on 09/04/2022.
//

import Foundation
import FAPages

public struct FASubmissionCommentNotificationPreview: Equatable, Hashable {
    public let cid: Int
    public let author: String
    public let displayAuthor: String
    public let submissionTitle: String
    public let datetime: String
    public let naturalDatetime: String
    public let submissionUrl: URL
    
    public init(cid: Int, author: String, displayAuthor: String, submissionTitle: String, datetime: String, naturalDatetime: String, submissionUrl: URL) {
        self.cid = cid
        self.author = author
        self.displayAuthor = displayAuthor
        self.submissionTitle = submissionTitle
        self.datetime = datetime
        self.naturalDatetime = naturalDatetime
        self.submissionUrl = submissionUrl
    }
}

extension FASubmissionCommentNotificationPreview: Identifiable {
    public var id: Int { cid }
}

public struct FAJournalNotificationPreview: Equatable, Hashable, Identifiable {
    public let id: Int
    public let author: String
    public let displayAuthor: String
    public let title: String
    public let datetime: String
    public let naturalDatetime: String
    public let journalUrl: URL
    
    public init(id: Int, author: String, displayAuthor: String, title: String, datetime: String, naturalDatetime: String, journalUrl: URL) {
        self.id = id
        self.author = author
        self.displayAuthor = displayAuthor
        self.title = title
        self.datetime = datetime
        self.naturalDatetime = naturalDatetime
        self.journalUrl = journalUrl
    }
}

public extension FASubmissionCommentNotificationPreview {
    init(_ comment: FANotificationsPage.SubmissionCommentHeader) {
        self.init(cid: comment.cid,
                  author: comment.author,
                  displayAuthor: comment.displayAuthor,
                  submissionTitle: comment.submissionTitle,
                  datetime: comment.datetime,
                  naturalDatetime: comment.naturalDatetime,
                  submissionUrl: comment.submissionUrl)
    }
}

public extension FAJournalNotificationPreview {
    init(_ journal: FANotificationsPage.JournalHeader) {
        self.init(id: journal.id,
                  author: journal.author,
                  displayAuthor: journal.displayAuthor,
                  title: journal.title,
                  datetime: journal.datetime,
                  naturalDatetime: journal.naturalDatetime,
                  journalUrl: journal.journalUrl)
    }
}
