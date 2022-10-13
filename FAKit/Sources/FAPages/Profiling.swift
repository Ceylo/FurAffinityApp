//
//  Profiling.swift
//  
//
//  Created by Ceylo on 22/09/2022.
//

import os
import Foundation

let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FAPages")
let signposter = OSSignposter(logger: logger)

enum FAPagesError: Error {
    case parserFailure(String, Int)
    
    static func parserFailureError(_ file: String = #file, _ line: Int = #line) -> FAPagesError {
        .parserFailure(file, line)
    }
}
