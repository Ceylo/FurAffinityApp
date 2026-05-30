//
//  URLSession+HTTPDataSource.swift
//
//
//  Created by Ceylo on 24/10/2021.
//

import Foundation

public struct CloudflareChallengeRequired: LocalizedError {
    public var errorDescription: String? {
        "furaffinity.net is requiring a CloudFlare challenge to continue browsing."
    }
}

extension URLSession: HTTPDataSource {
    enum Error: LocalizedError {
        case failureStatus(description: String)

        var errorDescription: String? {
            switch self {
            case let .failureStatus(description):
                description
            }
        }
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

        var hasAwaitedChallenge = false
        while true {
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

            let sentCFClearance = (self.configuration.httpCookieStorage?.cookies(for: url) ?? [])
                .first(where: { $0.name == "cf_clearance" })
            logger.info(
                "\(method, privacy: .public) request on \(requestDesc, privacy: .public)\(hasAwaitedChallenge ? " (retry post-challenge)" : "", privacy: .public)\(sentCFClearance.map { " with \($0.loggingDescription)" } ?? "", privacy: .public)"
            )
            let (data, response) = try await self.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw Error.failureStatus(description:  "\(url): request failed with non HTTP response \(response)")
            }

            let isCloudflareChallenge = httpResponse.value(forHTTPHeaderField: "cf-mitigated") == "challenge"
            if isCloudflareChallenge && !hasAwaitedChallenge {
                hasAwaitedChallenge = true
                logger.info("CloudFlare challenge encountered for \(url, privacy: .public); awaiting user resolution")
                try await CloudflareChallengeCoordinator.shared.awaitResolution()
                continue
            }

            guard (200...299).contains(httpResponse.statusCode) || (httpResponse.statusCode == 400 && !data.isEmpty)
            else {
                logger.error(
                    "\(url, privacy: .public): request failed with response \(response, privacy: .public) and received data \(String(data: data, encoding: .utf8) ?? "<non-UTF8 data>", privacy: .public)."
                )

                if isCloudflareChallenge {
                    throw CloudflareChallengeRequired()
                }

                throw Error.failureStatus(description:  "\(url): request failed with status \(httpResponse.statusCode) and response \(httpResponse)")
            }

            if httpResponse.statusCode == 400 {
                logger.warning("\(requestDesc, privacy: .public): got status code 400 but continuing since data was received")
            }
            return data
        }
    }
}
