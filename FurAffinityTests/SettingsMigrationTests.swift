//
//  SettingsMigrationTests.swift
//  FurAffinityTests
//
//  Created by Ceylo on 14/06/2026.
//

import Foundation
import Testing
import Defaults

@testable import Fur_Affinity

@Suite(.serialized)
struct SettingsMigrationTests {
    private func clearAllKeys() {
        for key in Defaults.Keys.all {
            UserDefaults.standard.removeObject(forKey: key.name)
        }
    }

    // Fresh install: no persisted settings → migrations are skipped and the false
    // default for badgeJournals must survive. Defaults registers every key's default
    // into the registration domain, so object(forKey:) is non-nil even on a fresh
    // install; we register one here to ensure detection relies on the persistent
    // domain only (this is the case the original implementation got wrong).
    @Test func freshInstall_keepsBadgeDefaults() {
        clearAllKeys()
        defer { clearAllKeys() }
        UserDefaults.standard.register(defaults: [Defaults.Keys.badgeNotes.name: true])

        Defaults.runSettingsMigrations()

        #expect(Defaults[.badgeJournals] == false)
        #expect(Defaults[.settingsSchemaVersion] == Defaults.currentSettingsSchemaVersion)
        // The badge migration body never ran.
        #expect(Defaults[.didMigrateBadgeSettings] == false)
    }

    // Legacy user with stored data but no schema version and not yet badge-migrated:
    // the badge toggles get seeded from the notification toggles.
    @Test func legacyUnmigrated_seedsBadgesFromNotifications() {
        clearAllKeys()
        defer { clearAllKeys() }

        Defaults[.notifyJournals] = true
        Defaults[.notifyShouts] = false   // differs from default → guarantees stored data

        Defaults.runSettingsMigrations()

        #expect(Defaults[.badgeJournals] == true)   // seeded from notifyJournals
        #expect(Defaults[.badgeShouts] == false)    // seeded from notifyShouts
        #expect(Defaults[.notifyJournals] == true)  // reset by the migration
        #expect(Defaults[.didMigrateBadgeSettings] == true)
        #expect(Defaults[.settingsSchemaVersion] == Defaults.currentSettingsSchemaVersion)
    }

    // Already at the current schema version: running migrations is a no-op.
    @Test func alreadyCurrent_isNoOp() {
        clearAllKeys()
        defer { clearAllKeys() }

        Defaults[.settingsSchemaVersion] = Defaults.currentSettingsSchemaVersion
        Defaults[.badgeJournals] = false
        Defaults[.notifyJournals] = true

        Defaults.runSettingsMigrations()

        #expect(Defaults[.badgeJournals] == false)
    }
}
