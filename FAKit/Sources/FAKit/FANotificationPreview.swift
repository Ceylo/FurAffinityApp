//
//  FANotePreview.swift
//  
//
//  Created by Ceylo on 09/04/2022.
//

import Foundation
import FAPages

public enum FANotificationPreview: Equatable, Hashable, Identifiable {
    public var id: Int {
        switch self {
        case let .journal(journal):
            return journal.id
        }
    }
    
    case journal(FAJournalNotificationPreview)
}

public struct FAJournalNotificationPreview: Equatable, Hashable {
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

public extension FANotificationPreview {
    init(_ header: FANotificationsPage.Header) {
        switch header {
        case let .journal(journal):
            self = .journal(
                .init(id: journal.id,
                      author: journal.author,
                      displayAuthor: journal.displayAuthor,
                      title: journal.title,
                      datetime: journal.datetime,
                      naturalDatetime: journal.naturalDatetime,
                      journalUrl: journal.journalUrl)
            )
        }
    }
}
