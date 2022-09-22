//
//  Model.swift
//  FurAffinity
//
//  Created by Ceylo on 21/11/2021.
//

import SwiftUI
import FAKit
import OrderedCollections

@MainActor
class Model: ObservableObject {
    static let autorefreshDelay: TimeInterval = 15 * 60
    
    @Published var session: FASession? {
        didSet {
            if session != nil {
                assert(oldValue == nil, "Session set twice")
            }
            processNewSession()
        }
    }
    @Published
    public private (set) var submissionPreviews = OrderedSet<FASubmissionPreview>()
    public private (set) var lastSubmissionPreviewsFetchDate: Date?
    
    @Published
    private (set) var notePreviews = OrderedSet<FANotePreview>()
    @Published
    private (set) var unreadNoteCount = 0
    public private (set) var lastNotePreviewsFetchDate: Date?
    
    init(session: FASession? = nil) {
        self.session = session
    }
    
    func fetchNewSubmissionPreviews() async -> Int {
        let latestSubmissions = await session?.submissionPreviews() ?? []
        lastSubmissionPreviewsFetchDate = Date()
        let newSubmissions = OrderedSet(latestSubmissions)
            .subtracting(submissionPreviews)
        
        if !newSubmissions.isEmpty {
            submissionPreviews = OrderedSet(newSubmissions).union(submissionPreviews)
        }
        return newSubmissions.count
    }
    
    func fetchNewNotePreviews() async {
        let latestNotes = await session?.notePreviews() ?? []
        notePreviews = OrderedSet(latestNotes)
        lastNotePreviewsFetchDate = Date()
    }
    
    private func processNewSession() {
        guard session != nil else {
            lastSubmissionPreviewsFetchDate = nil
            submissionPreviews.removeAll()
            return
        }
        
        Task {
            _ = await fetchNewSubmissionPreviews()
            await fetchNewNotePreviews()
        }
    }
}
