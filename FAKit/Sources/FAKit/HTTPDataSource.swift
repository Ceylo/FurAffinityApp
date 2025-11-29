//
//  HTTPDataSource.swift
//  
//
//  Created by Ceylo on 24/10/2021.
//

import Foundation

public enum HTTPMethod: String, CustomStringConvertible, Sendable {
    public var description: String { rawValue }
    
    case GET
    case POST
}

public protocol HTTPDataSource: Sendable {
    func httpData(from url: URL, cookies: [HTTPCookie]?,
                  method: HTTPMethod,
                  parameters: [URLQueryItem]) async throws -> Data
}

public extension HTTPDataSource {
    func httpData(from url: URL, cookies: [HTTPCookie]?) async throws -> Data {
        try await httpData(from: url, cookies: cookies, method: .GET, parameters: [])
    }
}
