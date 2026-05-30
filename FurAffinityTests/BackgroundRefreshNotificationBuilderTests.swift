//
//  FurAffinityTests.swift
//  FurAffinityTests
//
//  Created by Ceylo on 17/03/2023.
//

import FAKit
import Foundation
import Testing

@testable import Fur_Affinity

struct BackgroundRefreshNotificationBuilderTests {
    // MARK: - Helpers
    func makeSubmission(
        id: Int = 1,
        author: String = "author",
        display: String? = nil,
        title: String = "Submission Title"
    ) -> FASubmissionPreview {
        .init(
            sid: id,
            url: URL(string: "https://www.furaffinity.net/view/\(1000 + id)/")!,
            thumbnailUrl: URL(string: "https://t.furaffinity.net/\(1000 + id)@200-1637084699.jpg")!,
            thumbnailWidthOnHeightRatio: 1.0,
            title: title,
            author: author,
            displayAuthor: display ?? author.capitalized
        )
    }

    func makeNote(
        id: Int = 1,
        author: String = "author",
        display: String? = nil,
        title: String = "Note Title",
        unread: Bool = true
    ) -> FANotePreview {
        .init(
            id: id,
            author: author,
            displayAuthor: display ?? author.capitalized,
            title: title,
            datetime: "now",
            naturalDatetime: "now",
            unread: unread,
            noteUrl: URL(string: "https://www.furaffinity.net/msg/pms/1/\(id)/#message")!
        )
    }

    func makeNotification(
        id: Int = 1,
        author: String = "author",
        display: String? = nil,
        title: String = "Title",
        path: String = "/journal/"
    ) -> FANotificationPreview {
        .init(
            id: id,
            author: author,
            displayAuthor: display ?? author.capitalized,
            title: title,
            datetime: "now",
            naturalDatetime: "now",
            url: URL(string: "https://www.furaffinity.net\(path)\(1000 + id)/")!
        )
    }

    // MARK: - Tests

    @Test func noInputs_returnsEmpty() {
        let contents = BackgroundRefreshManager.buildNotifications(
            submissions: [],
            notes: [],
            submissionComments: [],
            journalComments: [],
            shouts: [],
            journals: []
        )
        #expect(contents.isEmpty)
    }

    @Test func eachNoteGetsItsOwnNotification() throws {
        let notes = [
            makeNote(id: 1, author: "alice", title: "Hello"),
            makeNote(id: 2, author: "alice", title: "World"),
        ]
        let contents = BackgroundRefreshManager.buildNotifications(
            submissions: [],
            notes: notes,
            submissionComments: [],
            journalComments: [],
            shouts: [],
            journals: []
        )

        #expect(contents.count == 2)
        #expect(contents[0].title == "New Note")
        #expect(contents[0].subtitle == "Alice")
        #expect(contents[0].body == "Hello")
        #expect(contents[1].title == "New Note")
        #expect(contents[1].subtitle == "Alice")
        #expect(contents[1].body == "World")
    }

    @Test func eachSubmissionCommentGetsItsOwnNotification() throws {
        let comments = [
            makeNotification(id: 1, author: "alice", title: "Nice!", path: "/view/"),
            makeNotification(id: 2, author: "alice", title: "Cool", path: "/view/"),
        ]
        let contents = BackgroundRefreshManager.buildNotifications(
            submissions: [],
            notes: [],
            submissionComments: comments,
            journalComments: [],
            shouts: [],
            journals: []
        )

        #expect(contents.count == 2)
        #expect(contents.allSatisfy { $0.title == "New Submission Comment" })
        #expect(contents.map(\.subtitle) == ["Alice", "Alice"])
        #expect(contents.map(\.body) == ["Nice!", "Cool"])
    }

    @Test func eachJournalCommentGetsItsOwnNotification() throws {
        let comments = [
            makeNotification(id: 1, author: "alice", title: "C1", path: "/journal/"),
            makeNotification(id: 2, author: "alice", title: "C2", path: "/journal/"),
        ]
        let contents = BackgroundRefreshManager.buildNotifications(
            submissions: [],
            notes: [],
            submissionComments: [],
            journalComments: comments,
            shouts: [],
            journals: []
        )

        #expect(contents.count == 2)
        #expect(contents.allSatisfy { $0.title == "New Journal Comment" })
        #expect(contents.map(\.subtitle) == ["Alice", "Alice"])
        #expect(contents.map(\.body) == ["C1", "C2"])
    }

    @Test func eachShoutGetsItsOwnNotification() throws {
        let shouts = [
            makeNotification(id: 1, author: "alice", title: "Hey!", path: "/user/"),
            makeNotification(id: 2, author: "alice", title: "Yo", path: "/user/"),
        ]
        let contents = BackgroundRefreshManager.buildNotifications(
            submissions: [],
            notes: [],
            submissionComments: [],
            journalComments: [],
            shouts: shouts,
            journals: []
        )

        #expect(contents.count == 2)
        #expect(contents.allSatisfy { $0.title == "New Shout" })
        #expect(contents.map(\.subtitle) == ["Alice", "Alice"])
        #expect(contents.map(\.body) == ["Hey!", "Yo"])
    }

    @Test func eachSubmissionGetsItsOwnNotification() throws {
        let submissions = [
            makeSubmission(id: 1, author: "alice", title: "S1"),
            makeSubmission(id: 2, author: "alice", title: "S2"),
            makeSubmission(id: 3, author: "bob", title: "S3"),
        ]
        let contents = BackgroundRefreshManager.buildNotifications(
            submissions: submissions,
            notes: [],
            submissionComments: [],
            journalComments: [],
            shouts: [],
            journals: []
        )

        #expect(contents.count == 3)
        #expect(contents.allSatisfy { $0.title == "New Submission" })
        #expect(contents.map(\.subtitle) == ["Alice", "Alice", "Bob"])
        #expect(contents.map(\.body) == ["S1", "S2", "S3"])
    }

    @Test func eachJournalGetsItsOwnNotification() throws {
        let journals = [
            makeNotification(id: 1, author: "alice", title: "J1", path: "/journal/"),
            makeNotification(id: 2, author: "bob", title: "J2", path: "/journal/"),
        ]
        let contents = BackgroundRefreshManager.buildNotifications(
            submissions: [],
            notes: [],
            submissionComments: [],
            journalComments: [],
            shouts: [],
            journals: journals
        )

        #expect(contents.count == 2)
        #expect(contents.allSatisfy { $0.title == "New Journal" })
        #expect(contents.map(\.subtitle) == ["Alice", "Bob"])
        #expect(contents.map(\.body) == ["J1", "J2"])
    }

    @Test func mixedReadAndUnreadNotes_onlyUnreadProduceNotifications() throws {
        let notes = [
            makeNote(id: 1, author: "alice", title: "Unread Note", unread: true),
            makeNote(id: 2, author: "bob", title: "Read Note", unread: false),
            makeNote(id: 3, author: "carol", title: "Another Unread", unread: true),
        ]
        let contents = BackgroundRefreshManager.buildNotifications(
            submissions: [],
            notes: notes,
            submissionComments: [],
            journalComments: [],
            shouts: [],
            journals: []
        )

        #expect(contents.count == 2)
        #expect(contents.allSatisfy { $0.title == "New Note" })
        #expect(contents.map(\.subtitle) == ["Alice", "Carol"])
        #expect(contents.map(\.body) == ["Unread Note", "Another Unread"])
    }

    @Test func allReadNotes_producesNoNotifications() throws {
        let notes = [
            makeNote(id: 1, author: "alice", title: "Old Note", unread: false),
            makeNote(id: 2, author: "bob", title: "Another Old Note", unread: false),
        ]
        let contents = BackgroundRefreshManager.buildNotifications(
            submissions: [],
            notes: notes,
            submissionComments: [],
            journalComments: [],
            shouts: [],
            journals: []
        )

        #expect(contents.isEmpty)
    }

    @Test func mixedActivity_producesOneNotificationPerItem() throws {
        let sub = makeSubmission(id: 1, author: "alice", title: "S1")
        let notes = [makeNote(id: 1, author: "bob", title: "N1")]
        let subComment = makeNotification(id: 1, author: "carol", title: "SC1", path: "/view/")
        let journalComment = makeNotification(id: 2, author: "dave", title: "JC1", path: "/journal/")
        let shout = makeNotification(id: 3, author: "eve", title: "Sh1", path: "/user/")
        let journal = makeNotification(id: 4, author: "alice", title: "AJ1", path: "/journal/")

        let contents = BackgroundRefreshManager.buildNotifications(
            submissions: [sub],
            notes: notes,
            submissionComments: [subComment],
            journalComments: [journalComment],
            shouts: [shout],
            journals: [journal]
        )

        #expect(contents.map(\.title) == [
            "New Submission",
            "New Note",
            "New Submission Comment",
            "New Journal Comment",
            "New Shout",
            "New Journal",
        ])
        #expect(contents.map(\.subtitle) == ["Alice", "Bob", "Carol", "Dave", "Eve", "Alice"])
        #expect(contents.map(\.body) == ["S1", "N1", "SC1", "JC1", "Sh1", "AJ1"])
    }
}
