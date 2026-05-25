//
//  FurAffinityTests.swift
//  FurAffinityTests
//
//  Created by Ceylo on 17/03/2023.
//

import Testing
@testable import Fur_Affinity
import UserNotifications

struct BackgroundRefreshNotificationBuilderTests {
    @Test func noCounts_returnsNil() throws {
        let notification = BackgroundRefreshManager.buildNotification(
            newSubmissions: 0,
            newNotes: 0,
            newSubmissionComments: 0,
            newJournalComments: 0,
            newShouts: 0,
            newJournals: 0
        )
        
        #expect(notification == nil)
    }

    @Test func countsPluralizationAndOrder() throws {
        // When
        let notification = try BackgroundRefreshManager.buildNotification(
            newSubmissions: 1,
            newNotes: 2,
            newSubmissionComments: 1,
            newJournalComments: 3,
            newShouts: 2,
            newJournals: 1
        ).unwrap()
        // Then
        #expect(notification.body == "1 submission, 2 notes, 1 submission comment, 3 journal comments, 2 shouts, 1 journal")
        #expect(notification.title == "New activity on Fur Affinity")
    }

    @Test func onlySomeCounts_includesOnlyThose_inOrder() throws {
        let content = try BackgroundRefreshManager.buildNotification(
            newSubmissions: 0,
            newNotes: 5,
            newSubmissionComments: 0,
            newJournalComments: 1,
            newShouts: 0,
            newJournals: 2
        ).unwrap()
        #expect(content.body == "5 notes, 1 journal comment, 2 journals")
    }
}
