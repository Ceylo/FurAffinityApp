//
//  LoggedInViewTabTests.swift
//  FurAffinityTests
//
//  Created by Ceylo on 02/06/2026.
//

import FAKit
import Foundation
import Testing

@testable import Fur_Affinity

struct LoggedInViewTabTests {
    private let url = URL(string: "https://www.furaffinity.net/")!

    private func metadata() -> FASubmission.Metadata {
        .init(
            title: "", author: "", displayAuthor: "", datetime: "", naturalDatetime: "",
            viewCount: 0, commentCount: 0, favoriteCount: 0, rating: .general,
            category: "", theme: "", species: "", resolution: "", fileSize: "",
            keywords: [], folders: []
        )
    }

    // Exhaustive over every FATarget case.

    @Test func submission_opensInSubmissions() {
        #expect(LoggedInView.Tab(deepLinkTarget: .submission(url: url, previewData: nil)) == .submissions)
    }

    @Test func note_opensInNotes() {
        #expect(LoggedInView.Tab(deepLinkTarget: .note(url: url)) == .notes)
    }

    @Test func journal_opensInNotifications() {
        #expect(LoggedInView.Tab(deepLinkTarget: .journal(url: url)) == .notifications)
    }

    @Test func user_opensInNotifications() {
        #expect(LoggedInView.Tab(deepLinkTarget: .user(url: url, previewData: nil)) == .notifications)
    }

    @Test func gallery_opensInNotifications() {
        #expect(LoggedInView.Tab(deepLinkTarget: .gallery(url: url)) == .notifications)
    }

    @Test func favorites_opensInNotifications() {
        #expect(LoggedInView.Tab(deepLinkTarget: .favorites(url: url)) == .notifications)
    }

    @Test func journals_opensInNotifications() {
        #expect(LoggedInView.Tab(deepLinkTarget: .journals(url: url)) == .notifications)
    }

    @Test func watchlist_opensInNotifications() {
        #expect(LoggedInView.Tab(deepLinkTarget: .watchlist(url: url)) == .notifications)
    }

    @Test func submissionMetadata_opensInNotifications() {
        #expect(LoggedInView.Tab(deepLinkTarget: .submissionMetadata(metadata())) == .notifications)
    }
}
