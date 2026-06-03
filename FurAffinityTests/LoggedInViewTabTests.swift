//
//  LoggedInViewTabTests.swift
//  FurAffinityTests
//
//  Created by Ceylo on 02/06/2026.
//

import Foundation
import Testing

@testable import Fur_Affinity

struct LoggedInViewTabTests {
    // A notification deep link keeps the current tab, except from Settings
    // (which has no navigation stack) where it falls back to Notifications.

    @Test func submissions_isPreserved() {
        #expect(LoggedInView.Tab.forDeepLink(current: .submissions) == .submissions)
    }

    @Test func notes_isPreserved() {
        #expect(LoggedInView.Tab.forDeepLink(current: .notes) == .notes)
    }

    @Test func notifications_isPreserved() {
        #expect(LoggedInView.Tab.forDeepLink(current: .notifications) == .notifications)
    }

    @Test func userpage_isPreserved() {
        #expect(LoggedInView.Tab.forDeepLink(current: .userpage) == .userpage)
    }

    @Test func settings_fallsBackToNotifications() {
        #expect(LoggedInView.Tab.forDeepLink(current: .settings) == .notifications)
    }
}
