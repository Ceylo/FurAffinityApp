//
//  OnlineFASessionTests.swift
//

import Testing
import Foundation
import FAPages
@testable import FAKit

private func makeLoggedInSession(extraData: [URL: Data] = [:]) async throws -> OnlineFASession {
    var data = [FAURLs.homeUrl: testData("www.furaffinity.net:loggedin.html")]
    data.merge(extraData) { _, new in new }
    let mock = MockHTTPDataSource(dataForUrl: data)
    let cookie = HTTPCookie(properties: [
        .name: "a",
        .value: "fakevalue",
        .domain: "furaffinity.net",
        .path: "/"
    ])!
    let session = try await OnlineFASession(cookies: [cookie], dataSource: mock)
    return try session.unwrap()
}

struct OnlineFASessionTests {
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
    func searchSubmissionPreviews_returnsResults() async throws {
        let searchUrl = FAURLs.searchUrl(for: .default)
        let session = try await makeLoggedInSession(extraData: [
            searchUrl: testData("www.furaffinity.net:search:")
        ])
        let previews = try await session.searchSubmissionPreviews(.default)
        #expect(previews.count == 72)
        #expect(previews.first?.sid == 65413735)
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
