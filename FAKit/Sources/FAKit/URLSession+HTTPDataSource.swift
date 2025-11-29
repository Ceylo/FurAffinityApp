//
//  URLSession+HTTPDataSource.swift
//
//
//  Created by Ceylo on 24/10/2021.
//

import Foundation

extension URLSession: HTTPDataSource {
    enum Error: LocalizedError {
        case failureStatus(description: String)
    }
    
    private func request(
        with url: URL,
        method: HTTPMethod,
        parameters: [URLQueryItem]
    ) -> (URLRequest, httpBody: String?) {
        
        var request: URLRequest
        let urlWithParams: URL
        if !parameters.isEmpty {
            urlWithParams = url.appending(queryItems: parameters)
        } else {
            urlWithParams = url
        }
        var httpBody: String?
        
        switch method {
        case .GET:
            request = URLRequest(url: urlWithParams)
            request.httpMethod = "GET"
        case .POST:
            request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            if let query = urlWithParams.query() {
                httpBody = query
                request.httpBody = query.data(using: .utf8)
            }
        }
        return (request, httpBody)
    }
    
    public func httpData(
        from url: URL,
        cookies: [HTTPCookie]?,
        method: HTTPMethod,
        parameters: [URLQueryItem]
    ) async throws -> Data {
        let state = signposter.beginInterval("Network Requests", "\(url)")
        defer { signposter.endInterval("Network Requests", state) }
        
        if let cookies = cookies {
            self.configuration.httpCookieStorage!
                .setCookies(cookies, for: url, mainDocumentURL: url)
        }
        let (request, httpBody) = request(
            with: url,
            method: method,
            parameters: parameters
        )
        let requestDesc: String
        if let httpBody {
            requestDesc = "\(request.url!) with body \"\(httpBody)\""
        } else {
            requestDesc = "\(request.url!)"
        }
        
        logger.info(
            "\(method, privacy: .public) request on \(requestDesc, privacy: .public)"
        )
        let (data, response) = try await self.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode)
        else {
            logger.error(
                "\(url, privacy: .public): request failed with response \(response, privacy: .public) and received data \(String(data: data, encoding: .utf8) ?? "<non-UTF8 data>", privacy: .public)."
            )
            throw Error.failureStatus(description:  "\(url): request failed with response \(response)")
        }
        
        return data
    }
}
