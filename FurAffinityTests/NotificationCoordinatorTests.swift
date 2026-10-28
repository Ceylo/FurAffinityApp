//
//  NotificationCoordinatorTests.swift
//  FurAffinityTests
//
//  Created by Ceylo on 02/06/2026.
//

import FAKit
import Foundation
import Testing

#if FA_SKIP_MODULE
@testable import FurAffinityUI
#else
@testable import Fur_Affinity
#endif

@MainActor
struct NotificationCoordinatorTests {
    private func target(forURLString urlString: String?) -> FATarget? {
        let coordinator = NotificationCoordinator()
        coordinator.setPendingDeepLink(fromURLString: urlString)
        return coordinator.pendingDeepLink
    }

    // MARK: - Valid URLs map to the expected target

    @Test func submissionURL_mapsToSubmission() {
        let urlString = "https://www.furaffinity.net/view/1234/"
        guard case let .submission(url, previewData) = target(forURLString: urlString) else {
            Issue.record("Expected .submission")
            return
        }
        #expect(url.absoluteString == urlString)
        #expect(previewData == nil)
    }

    @Test func submissionCommentURL_withFragment_mapsToSubmission() {
        let urlString = "https://www.furaffinity.net/view/1234/#cid:99"
        guard case let .submission(url, _) = target(forURLString: urlString) else {
            Issue.record("Expected .submission")
            return
        }
        #expect(url.absoluteString == urlString)
    }

    @Test func noteURL_mapsToNote() {
        let urlString = "https://www.furaffinity.net/msg/pms/1/55/#message"
        guard case let .note(url) = target(forURLString: urlString) else {
            Issue.record("Expected .note")
            return
        }
        #expect(url.absoluteString == urlString)
    }

    @Test func journalURL_mapsToJournal() {
        let urlString = "https://www.furaffinity.net/journal/77/"
        guard case let .journal(url) = target(forURLString: urlString) else {
            Issue.record("Expected .journal")
            return
        }
        #expect(url.absoluteString == urlString)
    }

    @Test func journalCommentURL_withFragment_mapsToJournal() {
        let urlString = "https://www.furaffinity.net/journal/77/#cid:5"
        guard case let .journal(url) = target(forURLString: urlString) else {
            Issue.record("Expected .journal")
            return
        }
        #expect(url.absoluteString == urlString)
    }

    @Test func shoutUserURL_mapsToUser() {
        let urlString = "https://www.furaffinity.net/user/somebody/"
        guard case let .user(url, previewData) = target(forURLString: urlString) else {
            Issue.record("Expected .user")
            return
        }
        #expect(url.absoluteString == urlString)
        #expect(previewData == nil)
    }

    // MARK: - Invalid / unmappable URLs leave pendingDeepLink nil

    @Test func nilString_leavesNil() {
        #expect(target(forURLString: nil) == nil)
    }

    @Test func emptyString_leavesNil() {
        #expect(target(forURLString: "") == nil)
    }

    @Test func nonFAURL_leavesNil() {
        #expect(target(forURLString: "https://example.com/view/1234/") == nil)
    }

    @Test func wellFormedButUnmappableFAURL_leavesNil() {
        #expect(target(forURLString: "https://www.furaffinity.net/unknownpath/42/") == nil)
    }

    // MARK: - userInfo extraction seam (driven by the delegate method)

    @Test func deepLinkURLString_presentKey_returnsString() {
        let urlString = "https://www.furaffinity.net/view/1234/"
        let userInfo: [AnyHashable: Any] = [NotificationDeepLink.urlKey: urlString]
        #expect(NotificationCoordinator.deepLinkURLString(fromUserInfo: userInfo) == urlString)
    }

    @Test func deepLinkURLString_missingKey_returnsNil() {
        let userInfo: [AnyHashable: Any] = ["other.key": "value"]
        #expect(NotificationCoordinator.deepLinkURLString(fromUserInfo: userInfo) == nil)
    }

    @Test func deepLinkURLString_nonStringValue_returnsNil() {
        let userInfo: [AnyHashable: Any] = [NotificationDeepLink.urlKey: 42]
        #expect(NotificationCoordinator.deepLinkURLString(fromUserInfo: userInfo) == nil)
    }

    // MARK: - Submission preview

    private let preview = FASubmissionPreview(
        sid: 1234,
        url: URL(string: "https://www.furaffinity.net/view/1234/")!,
        thumbnailUrl: URL(string: "https://t.furaffinity.net/1234@200-1637084699.jpg")!,
        thumbnailWidthOnHeightRatio: 1.0,
        title: "Title",
        author: "author",
        displayAuthor: "Author",
        rating: .general
    )

    @Test func submissionPreview_roundTripsThroughUserInfo() throws {
        let json = try #require(NotificationDeepLink.encode(preview))
        let userInfo: [AnyHashable: Any] = [NotificationDeepLink.submissionPreviewKey: json]
        #expect(NotificationCoordinator.submissionPreview(fromUserInfo: userInfo) == preview)
    }

    @Test func submissionPreview_missingOrGarbage_returnsNil() {
        #expect(NotificationCoordinator.submissionPreview(fromUserInfo: [:]) == nil)
        let userInfo: [AnyHashable: Any] = [NotificationDeepLink.submissionPreviewKey: "{not json"]
        #expect(NotificationCoordinator.submissionPreview(fromUserInfo: userInfo) == nil)
    }

    @Test func submissionURL_withPreview_carriesIt() {
        let coordinator = NotificationCoordinator()
        coordinator.setPendingDeepLink(fromURLString: preview.url.absoluteString, submissionPreview: preview)
        guard case let .submission(_, previewData) = coordinator.pendingDeepLink else {
            Issue.record("Expected .submission")
            return
        }
        #expect(previewData == preview)
    }

    @Test func nonSubmissionURL_ignoresPreview() {
        let coordinator = NotificationCoordinator()
        coordinator.setPendingDeepLink(fromURLString: "https://www.furaffinity.net/journal/77/", submissionPreview: preview)
        guard case .journal = coordinator.pendingDeepLink else {
            Issue.record("Expected .journal")
            return
        }
    }
}
