//
//  FurAffinityTests.swift
//  FurAffinityTests
//
//  Created by Ceylo on 17/03/2023.
//

import Defaults
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

    // MARK: - Record building

    @Test func noInputs_returnsEmpty() {
        let records = BackgroundRefreshManager.buildRecords(
            submissions: [],
            notes: [],
            submissionComments: [],
            journalComments: [],
            shouts: [],
            journals: []
        )
        #expect(records.isEmpty)
    }

    @Test func eachNoteGetsItsOwnNotification() throws {
        let notes = [
            makeNote(id: 1, author: "alice", title: "Hello"),
            makeNote(id: 2, author: "alice", title: "World"),
        ]
        let records = BackgroundRefreshManager.buildRecords(
            submissions: [],
            notes: notes,
            submissionComments: [],
            journalComments: [],
            shouts: [],
            journals: []
        )

        #expect(records.count == 2)
        #expect(records.map(\.title) == ["Alice", "Alice"])
        #expect(records.map(\.body) == ["✉️ Hello", "✉️ World"])
        #expect(records.map(\.author) == ["alice", "alice"])
        #expect(records.map(\.dedupKey) == ["note-1", "note-2"])
        #expect(records.allSatisfy { $0.thumbnailURLString == nil })
        #expect(records.map(\.url) == [
            "https://www.furaffinity.net/msg/pms/1/1/#message",
            "https://www.furaffinity.net/msg/pms/1/2/#message",
        ])
    }

    @Test func eachSubmissionCommentGetsItsOwnNotification() throws {
        let comments = [
            makeNotification(id: 1, author: "alice", title: "Nice!", path: "/view/"),
            makeNotification(id: 2, author: "alice", title: "Cool", path: "/view/"),
        ]
        let records = BackgroundRefreshManager.buildRecords(
            submissions: [],
            notes: [],
            submissionComments: comments,
            journalComments: [],
            shouts: [],
            journals: []
        )

        #expect(records.count == 2)
        #expect(records.map(\.title) == ["Alice", "Alice"])
        #expect(records.map(\.body) == ["💬 Nice!", "💬 Cool"])
        #expect(records.map(\.author) == ["alice", "alice"])
        #expect(records.map(\.dedupKey) == ["submission-comment-1", "submission-comment-2"])
        #expect(records.map(\.url) == [
            "https://www.furaffinity.net/view/1001/",
            "https://www.furaffinity.net/view/1002/",
        ])
    }

    @Test func eachJournalCommentGetsItsOwnNotification() throws {
        let comments = [
            makeNotification(id: 1, author: "alice", title: "C1", path: "/journal/"),
            makeNotification(id: 2, author: "alice", title: "C2", path: "/journal/"),
        ]
        let records = BackgroundRefreshManager.buildRecords(
            submissions: [],
            notes: [],
            submissionComments: [],
            journalComments: comments,
            shouts: [],
            journals: []
        )

        #expect(records.count == 2)
        #expect(records.map(\.title) == ["Alice", "Alice"])
        #expect(records.map(\.body) == ["💬 C1", "💬 C2"])
        #expect(records.map(\.author) == ["alice", "alice"])
        #expect(records.map(\.dedupKey) == ["journal-comment-1", "journal-comment-2"])
        #expect(records.map(\.url) == [
            "https://www.furaffinity.net/journal/1001/",
            "https://www.furaffinity.net/journal/1002/",
        ])
    }

    @Test func eachShoutGetsItsOwnNotification() throws {
        let shouts = [
            makeNotification(id: 1, author: "alice", title: "Hey!", path: "/user/"),
            makeNotification(id: 2, author: "alice", title: "Yo", path: "/user/"),
        ]
        let records = BackgroundRefreshManager.buildRecords(
            submissions: [],
            notes: [],
            submissionComments: [],
            journalComments: [],
            shouts: shouts,
            journals: []
        )

        #expect(records.count == 2)
        #expect(records.map(\.title) == ["Alice", "Alice"])
        #expect(records.map(\.body) == ["📣 Hey!", "📣 Yo"])
        #expect(records.map(\.author) == ["alice", "alice"])
        #expect(records.map(\.dedupKey) == ["shout-1", "shout-2"])
        #expect(records.map(\.url) == [
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
        let records = BackgroundRefreshManager.buildRecords(
            submissions: submissions,
            notes: [],
            submissionComments: [],
            journalComments: [],
            shouts: [],
            journals: []
        )

        #expect(records.count == 3)
        #expect(records.map(\.title) == ["Alice", "Alice", "Bob"])
        // Submissions drop the emoji prefix now that they carry a thumbnail attachment.
        #expect(records.map(\.body) == ["S1", "S2", "S3"])
        #expect(records.map(\.author) == ["alice", "alice", "bob"])
        #expect(records.map(\.dedupKey) == ["submission-1", "submission-2", "submission-3"])
        #expect(records.map(\.url) == [
            "https://www.furaffinity.net/view/1001/",
            "https://www.furaffinity.net/view/1002/",
            "https://www.furaffinity.net/view/1003/",
        ])
        // Submissions carry their resolved 400px thumbnail URL; general rating => no blur.
        #expect(records.map(\.thumbnailURLString) == [
            "https://t.furaffinity.net/1001@400-1637084699.jpg",
            "https://t.furaffinity.net/1002@400-1637084699.jpg",
            "https://t.furaffinity.net/1003@400-1637084699.jpg",
        ])
        #expect(records.map(\.needsBlur) == [false, false, false])
    }

    @Test func nonGeneralSubmissionNeedsBlur() throws {
        let submissions = [
            makeSubmission(id: 1, author: "alice", title: "S1", rating: .general),
            makeSubmission(id: 2, author: "bob", title: "S2", rating: .mature),
            makeSubmission(id: 3, author: "carol", title: "S3", rating: .adult),
        ]
        let records = BackgroundRefreshManager.buildRecords(
            submissions: submissions,
            notes: [],
            submissionComments: [],
            journalComments: [],
            shouts: [],
            journals: []
        )

        #expect(records.map(\.needsBlur) == [false, true, true])
        #expect(records.allSatisfy { $0.thumbnailURLString != nil })
    }

    @Test func eachJournalGetsItsOwnNotification() throws {
        let journals = [
            makeNotification(id: 1, author: "alice", title: "J1", path: "/journal/"),
            makeNotification(id: 2, author: "bob", title: "J2", path: "/journal/"),
        ]
        let records = BackgroundRefreshManager.buildRecords(
            submissions: [],
            notes: [],
            submissionComments: [],
            journalComments: [],
            shouts: [],
            journals: journals
        )

        #expect(records.count == 2)
        #expect(records.map(\.title) == ["Alice", "Bob"])
        #expect(records.map(\.body) == ["📝 J1", "📝 J2"])
        #expect(records.map(\.author) == ["alice", "bob"])
        #expect(records.map(\.dedupKey) == ["journal-1", "journal-2"])
        #expect(records.map(\.url) == [
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
        let records = BackgroundRefreshManager.buildRecords(
            submissions: [],
            notes: notes,
            submissionComments: [],
            journalComments: [],
            shouts: [],
            journals: []
        )

        #expect(records.count == 2)
        #expect(records.map(\.title) == ["Alice", "Carol"])
        #expect(records.map(\.body) == ["✉️ Unread Note", "✉️ Another Unread"])
        #expect(records.map(\.author) == ["alice", "carol"])
    }

    @Test func allReadNotes_producesNoNotifications() throws {
        let notes = [
            makeNote(id: 1, author: "alice", title: "Old Note", unread: false),
            makeNote(id: 2, author: "bob", title: "Another Old Note", unread: false),
        ]
        let records = BackgroundRefreshManager.buildRecords(
            submissions: [],
            notes: notes,
            submissionComments: [],
            journalComments: [],
            shouts: [],
            journals: []
        )

        #expect(records.isEmpty)
    }

    @Test func mixedActivity_producesOneNotificationPerItem() throws {
        let sub = makeSubmission(id: 1, author: "alice", title: "S1")
        let notes = [makeNote(id: 1, author: "bob", title: "N1")]
        let subComment = makeNotification(id: 1, author: "carol", title: "SC1", path: "/view/")
        let journalComment = makeNotification(id: 2, author: "dave", title: "JC1", path: "/journal/")
        let shout = makeNotification(id: 3, author: "eve", title: "Sh1", path: "/user/")
        let journal = makeNotification(id: 4, author: "alice", title: "AJ1", path: "/journal/")

        let records = BackgroundRefreshManager.buildRecords(
            submissions: [sub],
            notes: notes,
            submissionComments: [subComment],
            journalComments: [journalComment],
            shouts: [shout],
            journals: [journal]
        )

        #expect(records.map(\.title) == ["Alice", "Bob", "Carol", "Dave", "Eve", "Alice"])
        #expect(records.map(\.body) == ["S1", "✉️ N1", "💬 SC1", "💬 JC1", "📣 Sh1", "📝 AJ1"])
        #expect(records.map(\.author) == ["alice", "bob", "carol", "dave", "eve", "alice"])
        // Only the submission carries a thumbnail; the rest are nil.
        #expect(records.map { $0.thumbnailURLString != nil } == [true, false, false, false, false, false])
        #expect(records.map(\.dedupKey) == [
            "submission-1",
            "note-1",
            "submission-comment-1",
            "journal-comment-2",
            "shout-3",
            "journal-4",
        ])
        #expect(records.map(\.url) == [
            "https://www.furaffinity.net/view/1001/",            // submission, id 1
            "https://www.furaffinity.net/msg/pms/1/1/#message",  // note, id 1
            "https://www.furaffinity.net/view/1001/",            // submission comment, id 1
            "https://www.furaffinity.net/journal/1002/",         // journal comment, id 2
            "https://www.furaffinity.net/user/1003/",            // shout, id 3
            "https://www.furaffinity.net/journal/1004/",         // journal, id 4
        ])
    }

    // MARK: - Enqueue dedup

    private func record(_ dedupKey: String, body: String = "b") -> PendingNotificationRecord {
        PendingNotificationRecord(
            dedupKey: dedupKey,
            title: "T",
            body: body,
            author: "a",
            url: "https://www.furaffinity.net/",
            thumbnailURLString: nil,
            needsBlur: false
        )
    }

    @Test func enqueue_appendsToEmptyQueue() {
        let result = BackgroundRefreshManager.enqueue(
            [record("note-1"), record("note-2")],
            into: []
        )
        #expect(result.map(\.dedupKey) == ["note-1", "note-2"])
    }

    @Test func enqueue_skipsKeysAlreadyQueued() {
        let existing = [record("note-1"), record("shout-3")]
        let result = BackgroundRefreshManager.enqueue(
            [record("note-1"), record("note-2"), record("shout-3"), record("journal-5")],
            into: existing
        )
        // note-1 and shout-3 are already present; only the genuinely new ones append.
        #expect(result.map(\.dedupKey) == ["note-1", "shout-3", "note-2", "journal-5"])
    }

    // MARK: - Concurrent flush: resume / cancellation integrity

    private func queue(_ count: Int) -> [PendingNotificationRecord] {
        (1...count).map { record("note-\($0)") }
    }

    /// Tracks peak simultaneous executions to verify the concurrency bound.
    private actor ConcurrencyTracker {
        private var current = 0
        private(set) var peak = 0
        func enter() { current += 1; peak = max(peak, current) }
        func leave() { current -= 1 }
    }

    @Test func flush_uncancelledRun_postsAllAndEmptiesQueue() async {
        var persisted = queue(3)
        let outcome = await BackgroundRefreshManager.flushConcurrently(
            persisted,
            maxConcurrent: 6,
            post: { _ in .posted },
            persist: { persisted = $0 }
        )

        #expect(outcome == .init(postedCount: 3, cancelled: false))
        #expect(persisted.isEmpty)
    }

    @Test func flush_allCancelled_postsNothingAndLeavesQueueIntact() async {
        let initial = queue(3)
        var persisted = initial
        let outcome = await BackgroundRefreshManager.flushConcurrently(
            initial,
            maxConcurrent: 6,
            post: { _ in .cancelled },
            persist: { persisted = $0 }
        )

        #expect(outcome == .init(postedCount: 0, cancelled: true))
        #expect(persisted == initial)
    }

    @Test func flush_cancelledItemsStayQueued_postedAndSkippedRemoved() async {
        let initial = queue(5)
        var persisted = initial
        // note-2 cancelled mid-prep, note-4 a genuine post failure; the rest post.
        let outcome = await BackgroundRefreshManager.flushConcurrently(
            initial,
            maxConcurrent: 6,
            post: { rec in
                switch rec.dedupKey {
                case "note-2": return .cancelled
                case "note-4": return .skipped
                default: return .posted
                }
            },
            persist: { persisted = $0 }
        )

        #expect(outcome == .init(postedCount: 3, cancelled: true))
        // Only the cancelled item is stranded for the next run; posted + skipped are gone.
        #expect(persisted.map(\.dedupKey) == ["note-2"])
    }

    @Test func flush_emptyQueueDoesNothing() async {
        var persistCalls = 0
        let outcome = await BackgroundRefreshManager.flushConcurrently(
            [],
            maxConcurrent: 6,
            post: { _ in .posted },
            persist: { _ in persistCalls += 1 }
        )

        #expect(outcome == .init(postedCount: 0, cancelled: false))
        #expect(persistCalls == 0)
    }

    @Test func flush_respectsConcurrencyBound() async {
        let tracker = ConcurrencyTracker()
        let outcome = await BackgroundRefreshManager.flushConcurrently(
            queue(20),
            maxConcurrent: 4,
            post: { _ in
                await tracker.enter()
                // Yield so overlapping preparations actually coexist.
                try? await Task.sleep(nanoseconds: 1_000_000)
                await tracker.leave()
                return .posted
            },
            persist: { _ in }
        )

        #expect(outcome == .init(postedCount: 20, cancelled: false))
        let peak = await tracker.peak
        #expect(peak <= 4)
        #expect(peak >= 1)
    }

    // MARK: - Discard on app use

    @Test func discardPendingNotificationQueue_clearsTheQueue() {
        let saved = Defaults[.pendingNotificationQueue]
        defer { Defaults[.pendingNotificationQueue] = saved }

        Defaults[.pendingNotificationQueue] = queue(3)
        BackgroundRefreshManager.discardPendingNotificationQueue()
        #expect(Defaults[.pendingNotificationQueue].isEmpty)
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
}
