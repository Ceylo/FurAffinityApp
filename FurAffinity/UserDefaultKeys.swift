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
    static let notifySubmissionComments = Key<Bool>("notifySubmissionComments", default: true)
    static let notifyJournalComments = Key<Bool>("notifyJournalComments", default: true)
    static let notifyShouts = Key<Bool>("notifyShouts", default: true)
    static let notifyJournals = Key<Bool>("notifyJournals", default: false)
    
    static let notifications = [
        notifySubmissionComments,
        notifyJournalComments,
        notifyShouts,
        notifyJournals
    ]
    
    // MARK: - Sharing
    static let addMessageToSharedItems = Key<Bool>("addMessageToSharedItems", default: true)
    
    // MARK: - Convenience
    static let all = [
        lastViewedSubmissionID,
        animateAvatars
    ] + notifications
}
