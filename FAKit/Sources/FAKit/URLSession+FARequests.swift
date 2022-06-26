//
//  URLSession+FARequests.swift
//  
//
//  Created by Ceylo on 26/06/2022.
//

import Foundation

public extension URLSessionConfiguration {
    static let httpHeadersForFARequests: [String: String] = {
        // no using CFBundleIdentifier, we want this agent to be stable even if
        // bundle identifier changes
        let agent = "ceylo.FurAffinityApp"
        let version = Bundle.main.infoDictionary!["CFBundleShortVersionString"]!
        return ["User-Agent": "\(agent)/\(version)"]
    }()
}

public extension URLSession {
    /// The shared URLSession object to use when making requests to furaffinity.net website.
    /// This session comes with a custom user agent as asked by FA staff.
    static let sharedForFARequests: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = URLSessionConfiguration.httpHeadersForFARequests
        return URLSession(configuration: config)
    }()
}
