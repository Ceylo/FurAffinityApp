//
//  HTTPDataSource.swift
//  
//
//  Created by Ceylo on 24/10/2021.
//

import Foundation

public protocol HTTPDataSource {
    func httpData(from url: URL, cookies: [HTTPCookie]?,
                  completionHandler: @escaping (Data?) -> Void)
}

public extension HTTPDataSource {
    func httpData(from url: URL, cookies: [HTTPCookie]?) async -> Data? {
        await withCheckedContinuation { continuation in
            httpData(from: url, cookies: cookies) { data in
                continuation.resume(returning: data)
            }
        }
    }
}
