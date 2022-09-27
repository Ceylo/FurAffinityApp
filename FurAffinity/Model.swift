//
//  Model.swift
//  FurAffinity
//
//  Created by Ceylo on 21/11/2021.
//

import SwiftUI
import FAKit
import OrderedCollections

enum ModelError: Error {
    case disconnected
}

@MainActor
class Model: ObservableObject {
    static let autorefreshDelay: TimeInterval = 15 * 60
    
    @Published var session: FASession? {
        didSet {
            guard oldValue !== session else { return }
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
        unreadNoteCount = notePreviews.filter { $0.unread }.count
        lastNotePreviewsFetchDate = Date()
    }
    
    func toggleFavorite(for submission: FASubmission) async throws -> FASubmission? {
        guard let session else {
            throw ModelError.disconnected
        }
        
        let updated = await session.toggleFavorite(for: submission)
        if let updated {
            assert(updated.isFavorite != submission.isFavorite)
        }
        return updated
    }
    
    private func processNewSession() {
        guard session != nil else {
            lastSubmissionPreviewsFetchDate = nil
            submissionPreviews.removeAll()
            lastNotePreviewsFetchDate = nil
            notePreviews.removeAll()
            unreadNoteCount = 0
            return
        }
        
        Task {
            _ = await fetchNewSubmissionPreviews()
            await fetchNewNotePreviews()
        }
    }
}
