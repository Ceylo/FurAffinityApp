//
//  FANotePreview.swift
//  
//
//  Created by Ceylo on 09/04/2022.
//

import Foundation
import FAPages

public struct FANotificationPreview: Hashable, Identifiable, Sendable {
    public let id: Int
    public let author: String
    public let displayAuthor: String
    public let title: String
    public let datetime: String
    public let naturalDatetime: String
    public let url: URL
    
    public init(id: Int, author: String, displayAuthor: String, title: String, datetime: String, naturalDatetime: String, url: URL) {
        self.id = id
        self.author = author
        self.displayAuthor = displayAuthor
        self.title = title
        self.datetime = datetime
        self.naturalDatetime = naturalDatetime
        self.url = url
    }
}

public extension FANotificationPreview {
    init(_ header: FANotificationsPage.Header) {
        self.init(
            id: header.id,
            author: header.author,
            displayAuthor: header.displayAuthor,
            title: header.title,
            datetime: header.datetime,
            naturalDatetime: header.naturalDatetime,
            url: header.url
        )
    }
}
