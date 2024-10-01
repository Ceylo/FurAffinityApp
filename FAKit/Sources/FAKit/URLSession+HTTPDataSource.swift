//
//  URLSession+HTTPDataSource.swift
//  
//
//  Created by Ceylo on 24/10/2021.
//

import Foundation

extension URLSession: HTTPDataSource {
    private func request(with url: URL, method: HTTPMethod, parameters: [URLQueryItem]) -> URLRequest {
        
        var request: URLRequest
        let urlWithParams = url.appending(queryItems: parameters)
        
        switch method {
        case .GET:
            request = URLRequest(url: urlWithParams)
            request.httpMethod = "GET"
        case .POST:
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            if let query = urlWithParams.query() {
                logger.debug("\(query)")
                request.httpBody = query.data(using: .utf8)
            }
        }
        return request
    }
    
    public func httpData(
        from url: URL,
        cookies: [HTTPCookie]?,
        method: HTTPMethod,
        parameters: [URLQueryItem]
    ) async -> Data? {
        let state = signposter.beginInterval("Network Requests", "\(url)")
        defer { signposter.endInterval("Network Requests", state) }

        do {
            if let cookies = cookies {
                self.configuration.httpCookieStorage!
                    .setCookies(cookies, for: url, mainDocumentURL: url)
            }
            let request = request(with: url, method: method, parameters: parameters)
            
            logger.info("\(method, privacy: .public) request on \(url, privacy: .public)")
            let (data, response) = try await self.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode)
            else {
                logger.error("\(url, privacy: .public): request failed with response \(response, privacy: .public) and received data \(String(data: data, encoding: .utf8) ?? "<non-UTF8 data>", privacy: .public).")
                return nil
            }
            
            return data
        } catch {
            logger.error("\(url, privacy: .public): caught error: \(error, privacy: .public)")
            return nil
        }
    }
}
