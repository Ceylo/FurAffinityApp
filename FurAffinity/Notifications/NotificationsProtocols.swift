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
    func deleteNotifications(_ items: [FANotificationPreview], of kind: NotificationKind) -> Void
    func stageNotificationsDeletion(_ items: [FANotificationPreview], of kind: NotificationKind) -> Void
}

enum NotificationKind: CaseIterable {
    case submissionComment
    case journalComment
    case shout
    case journal
}

struct StagedNotification: Hashable {
    let kind: NotificationKind
    let preview: FANotificationPreview
    let index: Int
}

extension FANotificationPreviews {
    subscript(kind: NotificationKind) -> [FANotificationPreview] {
        switch kind {
        case .submissionComment: submissionComments
        case .journalComment: journalComments
        case .shout: shouts
        case .journal: journals
        }
    }

    func mapSections(
        _ transform: (NotificationKind, [FANotificationPreview]) -> [FANotificationPreview]
    ) -> FANotificationPreviews {
        FANotificationPreviews(
            submissionComments: transform(.submissionComment, submissionComments),
            journalComments: transform(.journalComment, journalComments),
            shouts: transform(.shout, shouts),
            journals: transform(.journal, journals)
        )
    }

    func removing(_ previews: [FANotificationPreview], of kind: NotificationKind) -> FANotificationPreviews {
        mapSections { sectionKind, section in
            sectionKind == kind ? section.filter { !previews.contains($0) } : section
        }
    }
}

/// Whether this platform delivers the notifications that `NotificationSettingsView`
/// configures. Android doesn't: delivery needs `BackgroundRefreshManager`.
enum NotificationDelivery {
#if os(Android)
    static let isSupported = false
#else
    static let isSupported = true
#endif
}
