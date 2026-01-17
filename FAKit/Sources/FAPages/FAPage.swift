//
//  FAPage.swift
//  FAKit
//
//  Created by Ceylo on 17/01/2026.
//

import Foundation

public protocol FAPage: Sendable, Equatable {
    init(data: Data, url: URL) async throws
}
