//
//  Commentable.swift
//  
//
//  Created by Ceylo on 17/04/2023.
//

import Foundation
import FAPages

public protocol FAPage: Sendable {
    init?(data: Data) async
}

public protocol Commentable: Sendable {
    associatedtype PageType: FAPage
    init(_ page: PageType, url: URL) async throws
    var url: URL { get }
}

extension FASubmissionPage: FAPage {}
extension FASubmission: Commentable {}

extension FAJournalPage: FAPage {}
extension FAJournal: Commentable {}
