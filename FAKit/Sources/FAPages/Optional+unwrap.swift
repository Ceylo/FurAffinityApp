//
//  Optional+unwrap.swift
//  
//
//  Created by Ceylo on 13/10/2022.
//

import Foundation

public extension Optional {
    enum Error: Swift.Error {
        case empty(String)
    }
    
    func unwrap(file: String = #file, line: Int = #line) throws -> Wrapped {
        guard let self else {
            throw Error.empty("Failed unwrapping optional at \(file):\(line)")
        }
        return self
    }
}
