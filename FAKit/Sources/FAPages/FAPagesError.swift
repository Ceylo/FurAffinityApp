//
//  FAPagesError.swift
//  FAKit
//
//  Created by Ceylo on 21/06/2025.
//

import Foundation

enum FAPagesError: LocalizedError {
    case unexpectedStructure
    case invalidParameter
    case parserFailure(String, Int)
    
    var errorDescription: String? {
        switch self {
        case .unexpectedStructure:
            return "Unexpected structure"
        case .invalidParameter:
            return "Invalid parameter"
        case .parserFailure(let file, let line):
            return "Parser failure in \(file):\(line)"
        }
    }
    
    static func parserFailureError(_ file: String = #file, _ line: Int = #line) -> FAPagesError {
        .parserFailure(file, line)
    }
}
