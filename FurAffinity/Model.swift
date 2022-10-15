//
//  Model.swift
//  FurAffinity
//
//  Created by Ceylo on 21/11/2021.
//

import SwiftUI
import FAKit

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
    public private (set) var submissionPreviews = [FASubmissionPreview]()
    public private (set) var lastSubmissionPreviewsFetchDate: Date?
    
    @Published
    private (set) var notePreviews = [FANotePreview]()
    @Published
    private (set) var unreadNoteCount = 0
    public private (set) var lastNotePreviewsFetchDate: Date?
    
    init(session: FASession? = nil) {
        self.session = session
    }
    
    func fetchNewSubmissionPreviews() async -> Int {
        let latestSubmissions = await session?.submissionPreviews() ?? []
        lastSubmissionPreviewsFetchDate = Date()
        let lastKnownSid = submissionPreviews.first?.sid ?? 0
        // We take advantage of the fact that submission IDs are always increasing
        // to know which one are new.
        let newSubmissions = latestSubmissions.filter { $0.sid > lastKnownSid }
        
        if !newSubmissions.isEmpty {
            submissionPreviews = newSubmissions + submissionPreviews
        }
        return newSubmissions.count
    }
    
    func fetchNewNotePreviews() async {
        notePreviews = await session?.notePreviews() ?? []
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
