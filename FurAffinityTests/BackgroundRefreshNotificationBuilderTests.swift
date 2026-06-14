//
//  FurAffinityTests.swift
//  FurAffinityTests
//
//  Created by Ceylo on 17/03/2023.
//

import FAKit
import Foundation
import Testing
import UserNotifications

@testable import Fur_Affinity

struct BackgroundRefreshNotificationBuilderTests {
    // MARK: - Helpers
    func makeSubmission(
        id: Int = 1,
        author: String = "author",
        display: String? = nil,
        title: String = "Submission Title",
        rating: Rating = .general
    ) -> FASubmissionPreview {
        .init(
            sid: id,
            url: URL(string: "https://www.furaffinity.net/view/\(1000 + id)/")!,
            thumbnailUrl: URL(string: "https://t.furaffinity.net/\(1000 + id)@200-1637084699.jpg")!,
            thumbnailWidthOnHeightRatio: 1.0,
            title: title,
            author: author,
            displayAuthor: display ?? author.capitalized,
            rating: rating
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

    func deepLinkURL(_ pending: PendingNotification) -> String? {
        pending.content.userInfo[NotificationDeepLink.urlKey] as? String
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
        #expect(contents[0].content.title == "Alice")
        #expect(contents[0].content.body == "✉️ Hello")
        #expect(contents[0].author == "alice")
        #expect(contents[1].content.title == "Alice")
        #expect(contents[1].content.body == "✉️ World")
        #expect(contents[1].author == "alice")
        #expect(contents.map(deepLinkURL) == [
            "https://www.furaffinity.net/msg/pms/1/1/#message",
            "https://www.furaffinity.net/msg/pms/1/2/#message",
        ])
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
        #expect(contents.map(\.content.title) == ["Alice", "Alice"])
        #expect(contents.map(\.content.body) == ["💬 Nice!", "💬 Cool"])
        #expect(contents.map(\.author) == ["alice", "alice"])
        #expect(contents.map(deepLinkURL) == [
            "https://www.furaffinity.net/view/1001/",
            "https://www.furaffinity.net/view/1002/",
        ])
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
        #expect(contents.map(\.content.title) == ["Alice", "Alice"])
        #expect(contents.map(\.content.body) == ["💬 C1", "💬 C2"])
        #expect(contents.map(\.author) == ["alice", "alice"])
        #expect(contents.map(deepLinkURL) == [
            "https://www.furaffinity.net/journal/1001/",
            "https://www.furaffinity.net/journal/1002/",
        ])
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
        #expect(contents.map(\.content.title) == ["Alice", "Alice"])
        #expect(contents.map(\.content.body) == ["📣 Hey!", "📣 Yo"])
        #expect(contents.map(\.author) == ["alice", "alice"])
        #expect(contents.map(deepLinkURL) == [
            "https://www.furaffinity.net/user/1001/",
            "https://www.furaffinity.net/user/1002/",
        ])
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
        #expect(contents.map(\.content.title) == ["Alice", "Alice", "Bob"])
        // Submissions drop the emoji prefix now that they carry a thumbnail attachment.
        #expect(contents.map(\.content.body) == ["S1", "S2", "S3"])
        #expect(contents.map(\.author) == ["alice", "alice", "bob"])
        #expect(contents.map(deepLinkURL) == [
            "https://www.furaffinity.net/view/1001/",
            "https://www.furaffinity.net/view/1002/",
            "https://www.furaffinity.net/view/1003/",
        ])
        // Submissions carry their thumbnail + rating for attachment building.
        #expect(contents.allSatisfy { $0.thumbnail != nil })
        #expect(contents.map(\.rating) == [.general, .general, .general])
    }

    @Test func nonGeneralSubmissionCarriesItsRating() throws {
        let submissions = [
            makeSubmission(id: 1, author: "alice", title: "S1", rating: .general),
            makeSubmission(id: 2, author: "bob", title: "S2", rating: .mature),
            makeSubmission(id: 3, author: "carol", title: "S3", rating: .adult),
        ]
        let contents = BackgroundRefreshManager.buildNotifications(
            submissions: submissions,
            notes: [],
            submissionComments: [],
            journalComments: [],
            shouts: [],
            journals: []
        )

        #expect(contents.map(\.rating) == [.general, .mature, .adult])
        #expect(contents.allSatisfy { $0.thumbnail != nil })
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
        #expect(contents.map(\.content.title) == ["Alice", "Bob"])
        #expect(contents.map(\.content.body) == ["📝 J1", "📝 J2"])
        #expect(contents.map(\.author) == ["alice", "bob"])
        #expect(contents.map(deepLinkURL) == [
            "https://www.furaffinity.net/journal/1001/",
            "https://www.furaffinity.net/journal/1002/",
        ])
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
        #expect(contents.map(\.content.title) == ["Alice", "Carol"])
        #expect(contents.map(\.content.body) == ["✉️ Unread Note", "✉️ Another Unread"])
        #expect(contents.map(\.author) == ["alice", "carol"])
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

        #expect(contents.map(\.content.title) == ["Alice", "Bob", "Carol", "Dave", "Eve", "Alice"])
        #expect(contents.map(\.content.body) == ["S1", "✉️ N1", "💬 SC1", "💬 JC1", "📣 Sh1", "📝 AJ1"])
        #expect(contents.map(\.author) == ["alice", "bob", "carol", "dave", "eve", "alice"])
        // Only the submission carries a thumbnail/rating; the rest are nil.
        #expect(contents.map { $0.thumbnail != nil } == [true, false, false, false, false, false])
        #expect(contents.map(\.rating) == [.general, nil, nil, nil, nil, nil])
        #expect(contents.map(deepLinkURL) == [
            "https://www.furaffinity.net/view/1001/",            // submission, id 1
            "https://www.furaffinity.net/msg/pms/1/1/#message",  // note, id 1
            "https://www.furaffinity.net/view/1001/",            // submission comment, id 1
            "https://www.furaffinity.net/journal/1002/",         // journal comment, id 2
            "https://www.furaffinity.net/user/1003/",            // shout, id 3
            "https://www.furaffinity.net/journal/1004/",         // journal, id 4
        ])
    }

    // MARK: - CloudFlare challenge failure notification

    @Test func challengeFailureNotificationContent() {
        let content = BackgroundRefreshManager.buildChallengeFailureNotification()
        #expect(content.title == "CloudFlare check required")
        #expect(content.body == "FurAffinity needs human verification. Open the app to resume notifications.")
    }

    @Test func challengeFailureNotificationIdentifierIsStable() {
        #expect(BackgroundRefreshManager.challengeFailureNotificationIdentifier == "fa.background.cf-challenge")
    }

    // MARK: - Flush cancellation integrity

    private func pendings(_ count: Int) -> [PendingNotification] {
        BackgroundRefreshManager.buildNotifications(
            submissions: [],
            notes: (1...count).map { makeNote(id: $0, title: "N\($0)") },
            submissionComments: [],
            journalComments: [],
            shouts: [],
            journals: []
        )
    }

    @Test func flush_uncancelledRun_postsAllAndCompletes() async {
        var posted = [String]()
        let outcome = await BackgroundRefreshManager.flush(
            pendings(3),
            isCancelled: { false },
            post: { pending in
                posted.append(pending.content.body)
                return .posted
            }
        )

        #expect(outcome == .init(postedCount: 3, cancelled: false))
        #expect(posted == ["✉️ N1", "✉️ N2", "✉️ N3"])
    }

    @Test func flush_cancelledBeforeAnyPost_postsNothingAndReportsCancelled() async {
        var postCalls = 0
        let outcome = await BackgroundRefreshManager.flush(
            pendings(3),
            isCancelled: { true },
            post: { _ in
                postCalls += 1
                return .posted
            }
        )

        #expect(outcome == .init(postedCount: 0, cancelled: true))
        #expect(postCalls == 0)
    }

    @Test func flush_cancelledMidRun_stopsAndReportsCancelled() async {
        var seen = 0
        // Top-of-loop guard cancels once the first item has been posted.
        let outcome = await BackgroundRefreshManager.flush(
            pendings(5),
            isCancelled: { seen >= 1 },
            post: { _ in
                seen += 1
                return .posted
            }
        )

        #expect(outcome == .init(postedCount: 1, cancelled: true))
    }

    @Test func flush_postReturnsCancelled_stopsAndReportsCancelled() async {
        var calls = 0
        // Cancellation lands mid-preparation of the second item.
        let outcome = await BackgroundRefreshManager.flush(
            pendings(5),
            isCancelled: { false },
            post: { _ in
                calls += 1
                return calls == 2 ? .cancelled : .posted
            }
        )

        #expect(outcome == .init(postedCount: 1, cancelled: true))
        #expect(calls == 2)
    }

    @Test func flush_skippedPostsDoNotCancelTheRun() async {
        var calls = 0
        // A genuine post failure (e.g. center.add threw) skips the item but keeps going.
        let outcome = await BackgroundRefreshManager.flush(
            pendings(3),
            isCancelled: { false },
            post: { _ in
                calls += 1
                return calls == 2 ? .skipped : .posted
            }
        )

        #expect(outcome == .init(postedCount: 2, cancelled: false))
        #expect(calls == 3)
    }
}
