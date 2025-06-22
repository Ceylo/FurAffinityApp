//
//  FAPagesError.swift
//  FAKit
//
//  Created by Ceylo on 21/06/2025.
//

enum FAPagesError: Error {
    case unexpectedStructure
    case invalidParameter
    case parserFailure(String, Int)
    
    static func parserFailureError(_ file: String = #file, _ line: Int = #line) -> FAPagesError {
        .parserFailure(file, line)
    }
}
