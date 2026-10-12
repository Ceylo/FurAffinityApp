//
//  OnlineFASessionTests.swift
//

import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FAPages
@testable import FAKit

private let authCookie = HTTPCookie(properties: [
    .name: "a",
    .value: "fakevalue",
    .domain: "furaffinity.net",
    .path: "/"
])!

private func makeLoggedInSession(extraData: [URL: Data] = [:]) async throws -> OnlineFASession {
    var data = [FAURLs.homeUrl: testData("www.furaffinity.net:loggedin.html")]
    data.merge(extraData) { _, new in new }
    let mock = MockHTTPDataSource(dataForUrl: data)
    let session = try await OnlineFASession(cookies: [authCookie], dataSource: mock)
    return try session.unwrap()
}

@MainActor
struct OnlineFASessionTests {
    @Test
    func feedSource_establishesSessionFromTheFeedAlone() async throws {
        let sid = 60097041
        let feedUrl = FAURLs.submissionsUrl(from: sid)
        let source = MockHTTPDataSource(dataForUrl: [
            feedUrl: testData("www.furaffinity.net:msg:submissions-firstpage.html")
        ])
        let session = try await OnlineFASession(
            cookies: [authCookie], dataSource: source, source: .submissionsFeed(from: sid)
        ).unwrap()
        #expect(session.username == "furrycount")
        #expect(session.displayUsername == "Furrycount")
        #expect(source.requestCount == 1)

        let previews = try await session.submissionPreviews(from: sid)
        #expect(previews.count == 72)
        #expect(source.requestCount == 1)

        // One-shot: the next fetch for the same position goes to the network.
        _ = try await session.submissionPreviews(from: sid)
        #expect(source.requestCount(for: feedUrl) == 2)
    }

    @Test
    func feedSource_otherPositionIsFetched() async throws {
        let sid = 60097041
        let feed = testData("www.furaffinity.net:msg:submissions-firstpage.html")
        let source = MockHTTPDataSource(dataForUrl: [
            FAURLs.submissionsUrl(from: sid): feed,
            FAURLs.latest72SubmissionsUrl: feed,
        ])
        let session = try await OnlineFASession(
            cookies: [authCookie], dataSource: source, source: .submissionsFeed(from: sid)
        ).unwrap()

        _ = try await session.submissionPreviews(from: nil)
        #expect(source.requestCount(for: FAURLs.latest72SubmissionsUrl) == 1)
        // A mismatch drops the prefetch rather than serving it later.
        _ = try await session.submissionPreviews(from: sid)
        #expect(source.requestCount(for: FAURLs.submissionsUrl(from: sid)) == 2)
    }

    @Test
    func feedSource_loggedOutPageThrowsLikeTheHomePage() async throws {
        let loggedOut = testData("www.furaffinity.net:loggedout.html")
        let source = MockHTTPDataSource(dataForUrl: [
            FAURLs.latest72SubmissionsUrl: loggedOut,
            FAURLs.homeUrl: loggedOut,
        ])
        await #expect(throws: OnlineFASession.Error.self) {
            try await OnlineFASession(
                cookies: [authCookie], dataSource: source, source: .submissionsFeed(from: nil)
            )
        }
    }

    @Test
    func feedSource_unparseableFeedFallsBackToHomePage() async throws {
        let source = MockHTTPDataSource(dataForUrl: [
            // Not UTF-8, so the feed parser throws.
            FAURLs.latest72SubmissionsUrl: Data([0xFF, 0xFE]),
            FAURLs.homeUrl: testData("www.furaffinity.net:loggedin.html"),
        ])
        let session = try await OnlineFASession(
            cookies: [authCookie], dataSource: source, source: .submissionsFeed(from: nil)
        ).unwrap()
        #expect(session.username == "furrycount")
        #expect(source.requestCount(for: FAURLs.homeUrl) == 1)
    }

    @Test
    func feedSource_noAuthCookieMakesNoRequest() async throws {
        let source = MockHTTPDataSource(dataForUrl: [:])
        let session = try await OnlineFASession(
            cookies: [], dataSource: source, source: .submissionsFeed(from: nil)
        )
        #expect(session == nil)
        #expect(source.requestCount == 0)
    }

    @Test
    func submission_returnsPopulatedSubmission() async throws {
        let submissionUrl = URL(string: "https://www.furaffinity.net/view/49338772/")!
        let session = try await makeLoggedInSession(extraData: [
            submissionUrl: testData("www.furaffinity.net:view:49338772-nocomment.html")
        ])
        let submission = try await session.submission(for: submissionUrl)
        #expect(!submission.title.isEmpty)
        #expect(!submission.author.isEmpty)
    }

    @Test
    func search_returnsResults() async throws {
        let searchUrl = FAURLs.searchUrl(for: .default)
        let session = try await makeLoggedInSession(extraData: [
            searchUrl: testData("www.furaffinity.net:search:")
        ])
        let results = try await session.search(.default)
        #expect(results.previews.count == 72)
        #expect(results.previews.first?.sid == 65413735)
        #expect(results.displayingRecentUploads == true)
        #expect(results.allowedRatings == [.general])
    }

    @Test
    func notePreviews_returnsPreviewsFromInbox() async throws {
        let session = try await makeLoggedInSession(extraData: [
            FAURLs.notesInboxUrl: testData("www.furaffinity.net:msg:pms-unread.html")
        ])
        let previews = try await session.notePreviews(from: .inbox)
        #expect(!previews.isEmpty)
    }

    @Test
    func notificationPreviews_returnsAllCategories() async throws {
        let session = try await makeLoggedInSession(extraData: [
            FAURLs.notificationsUrl: testData("www.furaffinity.net:msg:others-comments-journals-shout.html")
        ])
        let notifications = try await session.notificationPreviews()
        let hasAnyNotifications = !notifications.submissionComments.isEmpty
            || !notifications.journalComments.isEmpty
            || !notifications.shouts.isEmpty
            || !notifications.journals.isEmpty
        #expect(hasAnyNotifications)
    }

    @Test
    func user_returnsPopulatedUser() async throws {
        let userUrl = try FAURLs.userpageUrl(for: "terriniss")
        let session = try await makeLoggedInSession(extraData: [
            userUrl: testData("www.furaffinity.net:user:terriniss.html")
        ])
        let user = try await session.user(for: userUrl)
        #expect(!user.name.isEmpty)
        #expect(!user.displayName.isEmpty)
    }
}
