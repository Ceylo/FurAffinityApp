//
//  NotificationsProtocols.swift
//  FurAffinity
//
//  Created by Ceylo on 24/07/2026.
//

import FAKit

/// Split out of the notification views so `Model` can declare its conformances without
/// dragging the notifications UI into the Android build.
@MainActor
protocol NotificationsNuker: Sendable {
    func nukeAllSubmissionCommentNotifications() async throws -> Void
    func nukeAllJournalCommentNotifications() async throws -> Void
    func nukeAllShoutNotifications() async throws -> Void
    func nukeAllJournalNotifications() async throws -> Void
}

@MainActor
protocol NotificationsDeleter: Sendable {
    func deleteSubmissionCommentNotifications(_ items: [FANotificationPreview]) -> Void
    func deleteJournalCommentNotifications(_ items: [FANotificationPreview]) -> Void
    func deleteShoutNotifications(_ items: [FANotificationPreview]) -> Void
    func deleteJournalNotifications(_ items: [FANotificationPreview]) -> Void
}

/// Whether this platform delivers the notifications and tab badges that
/// `NotificationSettingsView` configures. Android has neither: delivery needs
/// `BackgroundRefreshManager`, and the badges sit on tabs that aren't ported.
enum NotificationDelivery {
#if os(Android)
    static let isSupported = false
#else
    static let isSupported = true
#endif
}
