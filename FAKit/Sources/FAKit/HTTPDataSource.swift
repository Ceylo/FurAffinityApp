//
//  HTTPDataSource.swift
//  
//
//  Created by Ceylo on 24/10/2021.
//

import Foundation

public enum HTTPMethod: String, CustomStringConvertible {
    public var description: String { rawValue }
    
    case GET
    case POST
}

public protocol HTTPDataSource {
    func httpData(from url: URL, cookies: [HTTPCookie]?,
                  method: HTTPMethod,
                  parameters: [URLQueryItem]) async -> Data?
}

public extension HTTPDataSource {
    func httpData(from url: URL, cookies: [HTTPCookie]?) async -> Data? {
        await httpData(from: url, cookies: cookies, method: .GET, parameters: [])
    }
}
