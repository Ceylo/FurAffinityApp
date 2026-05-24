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
    static let notifyJournals = Key<Bool>("notifyJournals", default: false)
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
        animateAvatars
    ] + notifications + latestNotificationIDs
}
