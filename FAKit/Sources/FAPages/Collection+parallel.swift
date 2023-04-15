//
//  File.swift
//  
//
//  Created by Ceylo on 15/04/2023.
//

import Foundation

extension Collection {
    func parallelMap<T>(_ transform: @escaping (Self.Element) throws -> T) async rethrows -> [T] {
        try await withThrowingTaskGroup(of: (Int, T).self) { group in
            for (offset, element) in enumerated() {
                group.addTask {
                    (offset, try transform(element))
                }
            }
            
            return try await group
                .reduce(into: [T?](repeating: nil, count: count),
                        { $0[$1.0] = $1.1})
            as! [T]
        }
    }
}
