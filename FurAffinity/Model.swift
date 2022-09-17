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
    @Published var session: FASession?
    @Published var submissionPreviews = OrderedSet<FASubmissionPreview>()
    
    func fetchNewSubmissionPreviews() async throws -> Int {
        let latestSubmissions = await session?.submissionPreviews() ?? []
        let newSubmissions = OrderedSet(latestSubmissions)
            .subtracting(submissionPreviews)
        
        if !newSubmissions.isEmpty {
            submissionPreviews = OrderedSet(newSubmissions).union(submissionPreviews)
        }
        return newSubmissions.count
    }
    
    init(session: FASession? = nil) {
        self.session = session
    }
}
