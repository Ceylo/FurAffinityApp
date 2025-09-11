//
//  Collection+async.swift
//
//
//  Created by Ceylo on 15/04/2023.
//

import Foundation

extension Collection where Element: Sendable {
    @inlinable public func asyncMap<T, E>(_ transform: (Element) async throws(E) -> T) async throws(E) -> [T] where E : Error {
        var results = [T]()
        for element in self {
            results.append(try await transform(element))
        }
        return results
    }
}
