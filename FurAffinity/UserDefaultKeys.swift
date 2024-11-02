//
//  UserDefaultKeys.swift
//  FurAffinity
//
//  Created by Ceylo on 06/10/2024.
//

import SwiftUI
import Defaults

extension Defaults.Keys {
    // Persistence
    static let lastViewedSubmissionID = Key<Int?>("lastViewedSubmissionID")
    
    // Display
    static let animateAvatars = Key<Bool>("animateAvatars", default: true)
    
    // Notifications
    static let notifySubmissionComments = Key<Bool>("notifySubmissionComments", default: true)
    static let notifyJournalComments = Key<Bool>("notifyJournalComments", default: true)
    static let notifyShouts = Key<Bool>("notifyShouts", default: true)
    static let notifyJournals = Key<Bool>("notifyJournals", default: false)
    
    static let all = [
        lastViewedSubmissionID,
        animateAvatars
    ] + notifications
    
    static let notifications = [
        notifySubmissionComments,
        notifyJournalComments,
        notifyShouts,
        notifyJournals
    ]
}
