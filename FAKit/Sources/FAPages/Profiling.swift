//
//  Profiling.swift
//  
//
//  Created by Ceylo on 22/09/2022.
//

import os
import Foundation

let FAPagesLogger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "FAPages")
let FAPagesSignposter = OSSignposter(logger: FAPagesLogger)

enum FAPagesError: Error {
    case parserFailure(String, Int)
    
    static func parserFailureError(_ file: String = #file, _ line: Int = #line) -> FAPagesError {
        .parserFailure(file, line)
    }
}
