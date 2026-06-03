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

    // Tab the target opens in is independent of `current` for these cases.

    @Test func submission_opensInSubmissions() {
        #expect(LoggedInView.Tab(deepLinkTarget: .submission(url: url, previewData: nil), current: .notes) == .submissions)
    }

    @Test func gallery_opensInSubmissions() {
        #expect(LoggedInView.Tab(deepLinkTarget: .gallery(url: url), current: .notes) == .submissions)
    }

    @Test func favorites_opensInSubmissions() {
        #expect(LoggedInView.Tab(deepLinkTarget: .favorites(url: url), current: .notes) == .submissions)
    }

    @Test func note_opensInNotes() {
        #expect(LoggedInView.Tab(deepLinkTarget: .note(url: url), current: .submissions) == .notes)
    }

    @Test func journal_opensInNotifications() {
        #expect(LoggedInView.Tab(deepLinkTarget: .journal(url: url), current: .submissions) == .notifications)
    }

    @Test func journals_opensInNotifications() {
        #expect(LoggedInView.Tab(deepLinkTarget: .journals(url: url), current: .submissions) == .notifications)
    }

    // user/watchlist aren't tied to a tab: they preserve `current`, unless
    // it's Settings (then they fall back to Notifications).

    @Test func user_preservesCurrentTab() {
        #expect(LoggedInView.Tab(deepLinkTarget: .user(url: url, previewData: nil), current: .notes) == .notes)
    }

    @Test func user_fromSettings_opensInNotifications() {
        #expect(LoggedInView.Tab(deepLinkTarget: .user(url: url, previewData: nil), current: .settings) == .notifications)
    }

    @Test func watchlist_preservesCurrentTab() {
        #expect(LoggedInView.Tab(deepLinkTarget: .watchlist(url: url), current: .userpage) == .userpage)
    }

    @Test func watchlist_fromSettings_opensInNotifications() {
        #expect(LoggedInView.Tab(deepLinkTarget: .watchlist(url: url), current: .settings) == .notifications)
    }
}
