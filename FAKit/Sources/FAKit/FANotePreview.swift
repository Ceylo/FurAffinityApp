//
//  FANotePreview.swift
//  
//
//  Created by Ceylo on 09/04/2022.
//

import Foundation
import FAPages

public struct FANotePreview: Equatable, Hashable {
    public let id: Int
    public let author: String
    public let displayAuthor: String
    public let title: String
    public let datetime: String
    public let naturalDatetime: String
    public let unread: Bool
    public let noteUrl: URL
    
    public init(id: Int, author: String, displayAuthor: String, title: String, datetime: String, naturalDatetime: String, unread: Bool, noteUrl: URL) {
        self.id = id
        self.author = author
        self.displayAuthor = displayAuthor
        self.title = title
        self.datetime = datetime
        self.naturalDatetime = naturalDatetime
        self.unread = unread
        self.noteUrl = noteUrl
    }
}

public extension FANotePreview {
    init(_ header: FANotesPage.NoteHeader) {
        self.init(id: header.id,
                  author: header.author,
                  displayAuthor: header.displayAuthor,
                  title: header.title,
                  datetime: header.datetime,
                  naturalDatetime: header.naturalDatetime,
                  unread: header.unread,
                  noteUrl: header.noteUrl)
    }
}
