//
//  UserDefaultKeys.swift
//  FurAffinity
//
//  Created by Ceylo on 06/10/2024.
//

import SwiftUI
import Defaults

extension Defaults.Keys {
    // MARK: - Persistence
    static let lastViewedSubmissionID = Key<Int?>("lastViewedSubmissionID")
    
    // MARK: - Display
    static let animateAvatars = Key<Bool>("animateAvatars", default: true)
    
    // MARK: - Notifications
    static let notifySubmissions = Key<Bool>("notifySubmissions", default: true)
    static let notifyNotes = Key<Bool>("notifyNotes", default: true)
    static let notifySubmissionComments = Key<Bool>("notifySubmissionComments", default: true)
    static let notifyJournalComments = Key<Bool>("notifyJournalComments", default: true)
    static let notifyShouts = Key<Bool>("notifyShouts", default: true)
    static let notifyJournals = Key<Bool>("notifyJournals", default: true)
    static let latestSubmissionNotificationID = Key<Int>("latestSubmissionNotificationID", default: 0)
    static let latestNoteNotificationID = Key<Int>("latestNoteNotificationID", default: 0)
    static let latestSubmissionCommentNotificationID = Key<Int>("latestSubmissionCommentNotificationID", default: 0)
    static let latestJournalCommentNotificationID = Key<Int>("latestJournalCommentNotificationID", default: 0)
    static let latestShoutNotificationID = Key<Int>("latestShoutNotificationID", default: 0)
    static let latestJournalNotificationID = Key<Int>("latestJournalNotificationID", default: 0)
    
    static let notifications = [
        notifySubmissions,
        notifyNotes,
        notifySubmissionComments,
        notifyJournalComments,
        notifyShouts,
        notifyJournals
    ]

    // MARK: - Badges
    static let badgeNotes = Key<Bool>("badgeNotes", default: true)
    static let badgeSubmissionComments = Key<Bool>("badgeSubmissionComments", default: true)
    static let badgeJournalComments = Key<Bool>("badgeJournalComments", default: true)
    static let badgeShouts = Key<Bool>("badgeShouts", default: true)
    static let badgeJournals = Key<Bool>("badgeJournals", default: false)

    static let badges = [
        badgeNotes,
        badgeSubmissionComments,
        badgeJournalComments,
        badgeShouts,
        badgeJournals
    ]

    // MARK: - Migration
    static let didMigrateBadgeSettings = Key<Bool>("didMigrateBadgeSettings", default: false)

    static let latestNotificationIDs = [
        latestSubmissionNotificationID,
        latestNoteNotificationID,
        latestSubmissionCommentNotificationID,
        latestJournalCommentNotificationID,
        latestShoutNotificationID,
        latestJournalNotificationID
    ]
    
    // MARK: - Sharing
    static let addMessageToSharedItems = Key<Bool>("addMessageToSharedItems", default: true)
    
    // MARK: - Convenience
    static let all = [
        lastViewedSubmissionID,
        animateAvatars,
        didMigrateBadgeSettings
    ] + notifications + badges + latestNotificationIDs
}

extension Defaults {
    /// Seeds the per-content badge toggles from the existing notification toggles so that
    /// users upgrading from a build where a single set of toggles drove both iOS notifications
    /// and tab badges keep their current badge behavior. Runs once.
    static func migrateBadgeSettingsIfNeeded() {
        guard !Defaults[.didMigrateBadgeSettings] else { return }
        Defaults[.badgeNotes] = Defaults[.notifyNotes]
        Defaults[.badgeSubmissionComments] = Defaults[.notifySubmissionComments]
        Defaults[.badgeJournalComments] = Defaults[.notifyJournalComments]
        Defaults[.badgeShouts] = Defaults[.notifyShouts]
        Defaults[.badgeJournals] = Defaults[.notifyJournals]
        Defaults[.notifyJournals] = true
        Defaults[.didMigrateBadgeSettings] = true
    }
}
