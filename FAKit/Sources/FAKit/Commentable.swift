//
//  Commentable.swift
//  
//
//  Created by Ceylo on 17/04/2023.
//

import Foundation
import FAPages

public protocol Commentable: Sendable {
    associatedtype PageType: FAPage
    init(_ page: PageType, url: URL) async throws
    var url: URL { get }
}

extension FASubmission: Commentable {}
extension FAJournal: Commentable {}
