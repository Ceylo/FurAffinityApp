//
//  Collection+parallel.swift
//  
//
//  Created by Ceylo on 15/04/2023.
//

import Foundation

extension Collection where Element: Sendable {
    // Using static method to workaround this warning:
    // Capture of non-Sendable type 'Self.Type' in an isolated closure
    static private func parallelMap<InputElement: Sendable, OutputElement: Sendable>(
        of collection: some Collection<InputElement>,
        _ transform: @Sendable @escaping (InputElement) throws -> OutputElement
    ) async rethrows -> [OutputElement] {
        return try await withThrowingTaskGroup(of: (Int, OutputElement).self) { group in
            for (offset, element) in collection.enumerated() {
                group.addTask {
                    (offset, try transform(element))
                }
            }
            
            return try await group
                .reduce(into: [OutputElement?](repeating: nil, count: collection.count),
                        { $0[$1.0] = $1.1})
            as! [OutputElement]
        }
    }
    
    public func parallelMap<T: Sendable>(_ transform: @Sendable @escaping (Element) throws -> T) async rethrows -> [T] {
        try await Self.parallelMap(of: self, transform)
    }
    
    static private func parallelMap<InputElement: Sendable, OutputElement: Sendable>(of collection: some Collection<InputElement>, _ transform: @Sendable @escaping (InputElement) async throws -> OutputElement) async rethrows -> [OutputElement] {
        try await withThrowingTaskGroup(of: (Int, OutputElement).self) { group in
            for (offset, element) in collection.enumerated() {
                group.addTask {
                    await (offset, try transform(element))
                }
            }
            
            return try await group
                .reduce(into: [OutputElement?](repeating: nil, count: collection.count),
                        { $0[$1.0] = $1.1})
            as! [OutputElement]
        }
    }
    
    public func parallelMap<T: Sendable>(_ transform: @Sendable @escaping (Element) async throws -> T) async rethrows -> [T] {
        try await Self.parallelMap(of: self, transform)
    }
    
    @inlinable public func asyncMap<T, E>(_ transform: (Element) async throws(E) -> T) async throws(E) -> [T] where E : Error {
        var results = [T]()
        for element in self {
            results.append(try await transform(element))
        }
        return results
    }
}
