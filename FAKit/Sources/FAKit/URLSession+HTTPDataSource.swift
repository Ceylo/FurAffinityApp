//
//  URLSession+HTTPDataSource.swift
//  
//
//  Created by Ceylo on 24/10/2021.
//

import Foundation

extension URLSession: HTTPDataSource {
    public func httpData(from url: URL, cookies: [HTTPCookie]?) async -> Data? {
        let state = signposter.beginInterval("Network Requests", "\(url)")
        defer { signposter.endInterval("Network Requests", state) }

        do {
            if let cookies = cookies {
                self.configuration.httpCookieStorage!
                    .setCookies(cookies, for: url, mainDocumentURL: url)
            }
            logger.info("Requesting data from \(url, privacy: .public)")
            let (data, response) = try await self.data(from: url, delegate: nil)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode)
            else {
                logger.error("\(url, privacy: .public): request failed with response \(response, privacy: .public) and received data \(String(data: data, encoding: .utf8) ?? "<non-UTF8 data>").")
                return nil
            }
            
            return data
        } catch {
            logger.error("\(url, privacy: .public): caught error: \(error)")
            return nil
        }
    }
}
