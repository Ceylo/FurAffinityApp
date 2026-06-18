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
    /// Notifications discovered by a background refresh but not yet posted. Persisted
    /// before the slow media+post phase so an expired run resumes the remainder.
    static let pendingNotificationQueue = Key<[PendingNotificationRecord]>("pendingNotificationQueue", default: [])
    
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
    /// Current settings schema version. Bump when adding a migration below.
    static let settingsSchemaVersion = Key<Int>("settingsSchemaVersion", default: 0)
    /// Legacy flag from the first (pre-versioning) migration. Read-only signal now.
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
        settingsSchemaVersion,
        didMigrateBadgeSettings
    ] + notifications + badges + latestNotificationIDs
}

extension Defaults {
    static let currentSettingsSchemaVersion = 1

    /// Runs each pending settings migration in order, stamping the schema version as it
    /// goes. A no-op once the version is at the current one.
    static func runSettingsMigrations() {
        var version = startingSchemaVersion()
        while version < currentSettingsSchemaVersion {
            version += 1
            runMigration(to: version)
            Defaults[.settingsSchemaVersion] = version
        }
        Defaults[.settingsSchemaVersion] = max(version, currentSettingsSchemaVersion)
    }

    /// Dispatches a single migration step. Add a case for each new schema version.
    private static func runMigration(to version: Int) {
        switch version {
        case 1: migrateBadgeSettings()
        default: break
        }
    }

    /// Determines where to begin migrating. Once `settingsSchemaVersion` is persisted this
    /// returns it; otherwise it infers the version for the transition release: fresh
    /// installs skip all migrations, legacy users resume from their last state.
    ///
    /// Detection uses the persistent domain (values actually written by the app) rather
    /// than `object(forKey:)`, because `Defaults` registers every key's default into the
    /// registration domain — so `object(forKey:)` is never `nil` and cannot tell a fresh
    /// install from a real one.
    private static func startingSchemaVersion() -> Int {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let persisted = UserDefaults.standard.persistentDomain(forName: bundleID)
        else { return currentSettingsSchemaVersion }

        if let version = persisted[Keys.settingsSchemaVersion.name] as? Int {
            return version
        }
        let ownKeyNames = Set(Keys.all.map(\.name))
        guard persisted.keys.contains(where: ownKeyNames.contains) else {
            return currentSettingsSchemaVersion   // fresh install
        }
        return persisted[Keys.didMigrateBadgeSettings.name] as? Bool == true ? 1 : 0
    }

    /// v1: seed the per-content badge toggles from the legacy notification toggles so that
    /// users upgrading from a build where a single set of toggles drove both iOS
    /// notifications and tab badges keep their current badge behavior.
    private static func migrateBadgeSettings() {
        Defaults[.badgeNotes] = Defaults[.notifyNotes]
        Defaults[.badgeSubmissionComments] = Defaults[.notifySubmissionComments]
        Defaults[.badgeJournalComments] = Defaults[.notifyJournalComments]
        Defaults[.badgeShouts] = Defaults[.notifyShouts]
        Defaults[.badgeJournals] = Defaults[.notifyJournals]
        Defaults[.notifyJournals] = true
        Defaults[.didMigrateBadgeSettings] = true
    }
}
