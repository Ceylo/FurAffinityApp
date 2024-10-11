//
//  FAUser.swift
//  
//
//  Created by Ceylo on 19/03/2023.
//

import Foundation
import FAPages

public struct FAUserJournals: Equatable, Sendable {
    public let displayAuthor: String
    
    public typealias Journal = FAUserJournalsPage.Journal
    public let journals: [Journal]
    
    public init(displayAuthor: String, journals: [Journal]) {
        self.displayAuthor = displayAuthor
        self.journals = journals
    }
}

public extension FAUserJournals {
    init(_ page: FAUserJournalsPage) async throws {
        self.init(
            displayAuthor: page.displayAuthor,
            journals: page.journals
        )
    }
}
