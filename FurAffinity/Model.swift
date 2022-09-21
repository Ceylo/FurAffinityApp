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
    @Published var session: FASession? {
        didSet {
            if session != nil {
                assert(oldValue == nil, "Session set twice")
            }
            processNewSession()
        }
    }
    @Published var submissionPreviews = OrderedSet<FASubmissionPreview>()
    public var lastFetchDate: Date?
    
    init(session: FASession? = nil) {
        self.session = session
    }
    
    func fetchNewSubmissionPreviews() async throws -> Int {
        let latestSubmissions = await session?.submissionPreviews() ?? []
        lastFetchDate = Date()
        let newSubmissions = OrderedSet(latestSubmissions)
            .subtracting(submissionPreviews)
        
        if !newSubmissions.isEmpty {
            submissionPreviews = OrderedSet(newSubmissions).union(submissionPreviews)
        }
        return newSubmissions.count
    }
    
    private func processNewSession() {
        guard session != nil else {
            lastFetchDate = nil
            submissionPreviews.removeAll()
            return
        }
        
        Task {
            try await fetchNewSubmissionPreviews()
        }
    }
}
