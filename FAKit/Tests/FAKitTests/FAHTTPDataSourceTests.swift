//
//  FAHTTPDataSourceTests.swift
//  FAKitTests
//
//  Pins the Android page transport's behaviour against a scripted fake, so the
//  Cloudflare work that follows shows up as a visible diff here rather than as a
//  silent change on the wire. The type lives under `Android/` but is unguarded and
//  platform-neutral, so it runs in this suite like anything else.
//

import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import FAKit

/// Canned responses, as members so a script reads `[.challenge(), .ok()]`.
extension FANativeHTTPResponse {
    static func challenge(protocol networkProtocol: String = "http/1.1") -> Self {
        Self(
            statusCode: 403,
            headers: ["cf-mitigated": "challenge"],
            body: Data(),
            networkProtocol: networkProtocol
        )
    }

    static func ok(_ body: String = "<html></html>") -> Self {
        Self(
            statusCode: 200,
            headers: ["content-type": "text/html"],
            body: Data(body.utf8),
            networkProtocol: "http/1.1"
        )
    }
}

/// Replays canned responses in order (the last one repeats forever) and records
/// every request and every repair, so a test can assert on both what went out and
/// in what order the transport was driven.
actor ScriptedTransport {
    enum Call: Equatable {
        case perform
        case repair(observed: UInt64)
        case epoch
    }

    private var responses: [FANativeHTTPResponse]
    private(set) var requests = [FANativeHTTPRequest]()
    private(set) var calls = [Call]()
    private(set) var epoch: UInt64

    init(_ responses: [FANativeHTTPResponse], epoch: UInt64 = 1) {
        self.responses = responses
        self.epoch = epoch
    }

    private func perform(_ request: FANativeHTTPRequest) -> FANativeHTTPResponse {
        requests.append(request)
        calls.append(.perform)
        let response = responses.count > 1 ? responses.removeFirst() : (responses.first ?? .ok())
        var stamped = response
        stamped.connectionEpoch = epoch
        return stamped
    }

    private func repair(observed: UInt64) -> UInt64 {
        calls.append(.repair(observed: observed))
        if CloudflareConnectionRepair.shouldEvict(observed: observed, current: epoch) {
            epoch += 1
        }
        return epoch
    }

    private func readEpoch() -> UInt64 {
        calls.append(.epoch)
        return epoch
    }

    nonisolated var transport: FANativeTransport {
        FANativeTransport(
            perform: { await self.perform($0) },
            repairConnections: { await self.repair(observed: $0) },
            currentEpoch: { await self.readEpoch() }
        )
    }

    /// `calls` without the bookkeeping `epoch` reads, which every request makes.
    var significantCalls: [Call] { calls.filter { $0 != .epoch } }
}

struct FAHTTPDataSourceTests {
    private static let feedURL = URL(string: "https://www.furaffinity.net/msg/submissions/")!

    private static func dataSource(
        transport: ScriptedTransport,
        cookieHeader: String = "a=auth; b=sess; cf_clearance=CLEAR",
        webViewFetch: FAHTTPDataSource.WebViewFetch? = nil,
        resolve: @escaping FAHTTPDataSource.ChallengeResolver = { throw CloudflareChallengeRequired() }
    ) -> FAHTTPDataSource {
        FAHTTPDataSource(
            userAgent: "TestAgent/1.0",
            cookieHeader: cookieHeader,
            webViewFetch: webViewFetch,
            nativeTransport: transport.transport,
            awaitChallengeResolution: resolve
        )
    }

    // MARK: - The wire request

    /// The POST body is what `URLComponents.percentEncodedQuery` produces, and it is
    /// pure ASCII — which is what lets a native transport carry it as a JSON string
    /// without ever changing a byte.
    @Test func postBodyIsPercentEncodedASCIIForm() async throws {
        let transport = ScriptedTransport([.ok()])
        let source = Self.dataSource(transport: transport)

        _ = try await source.httpData(
            from: URL(string: "https://www.furaffinity.net/journal/1/")!,
            cookies: nil, method: .POST,
            parameters: [
                URLQueryItem(name: "action", value: "reply"),
                URLQueryItem(name: "body", value: "héllo & wörld"),
            ]
        )

        let request = try #require(await transport.requests.first)
        let body = try #require(request.body)
        #expect(body == "action=reply&body=h%C3%A9llo%20%26%20w%C3%B6rld")
        let isASCII = body.unicodeScalars.allSatisfy(\.isASCII)
        #expect(isASCII)
        #expect(request.headers["Content-Type"] == "application/x-www-form-urlencoded")
    }

    /// A GET carries its parameters in the URL and no body at all.
    @Test func getPutsParametersInTheURL() async throws {
        let transport = ScriptedTransport([.ok()])
        let source = Self.dataSource(transport: transport)

        _ = try await source.httpData(
            from: URL(string: "https://www.furaffinity.net/search/")!,
            cookies: nil, method: .GET,
            parameters: [URLQueryItem(name: "q", value: "fox")]
        )

        let request = try #require(await transport.requests.first)
        #expect(request.body == nil)
        #expect(request.url.absoluteString == "https://www.furaffinity.net/search/?q=fox")
    }

    /// OkHttp's `BridgeInterceptor` adds `Accept-Encoding: gzip` and gunzips the
    /// response transparently *only* when we have not set that header ourselves. So
    /// its absence here is load-bearing, not an oversight.
    @Test func browserHeadersSetNoAcceptEncoding() {
        let names = FAHTTPDataSource.browserHeaders.map { $0.0.lowercased() }
        let hasAcceptEncoding = names.contains("accept-encoding")
        #expect(!hasAcceptEncoding)
    }

    @Test func credentialsGoToFAHostsOnly() async throws {
        let transport = ScriptedTransport([.ok()])
        let source = Self.dataSource(transport: transport)

        _ = try await source.httpData(from: Self.feedURL, cookies: nil)
        let toFA = try #require(await transport.requests.last)
        #expect(toFA.userAgent == "TestAgent/1.0")
        #expect(toFA.cookieHeader == "a=auth; b=sess; cf_clearance=CLEAR")
        #expect(toFA.headers["sec-fetch-mode"] == "navigate")

        _ = try await source.httpData(from: URL(string: "https://example.com/x")!, cookies: nil)
        let elsewhere = try #require(await transport.requests.last)
        #expect(elsewhere.userAgent == nil)
        #expect(elsewhere.cookieHeader == nil)
        #expect(elsewhere.headers["sec-fetch-mode"] == nil)
    }

    // MARK: - The cookie merge

    /// The base header is what the WebView itself would send, and Cloudflare compares
    /// against exactly that — so the base wins on a name collision and keeps its order,
    /// and per-request cookies are only appended when they add a name.
    @Test func cookieMergeKeepsBaseOrderAndWins() {
        let source = Self.dataSource(transport: ScriptedTransport([.ok()]))
        let extra = [
            HTTPCookie(properties: [.name: "a", .value: "OTHER", .domain: ".furaffinity.net", .path: "/"])!,
            HTTPCookie(properties: [.name: "z", .value: "new", .domain: ".furaffinity.net", .path: "/"])!,
        ]

        #expect(source.cookieHeader(merging: extra, base: "a=auth; b=sess") == "a=auth; b=sess; z=new")
        #expect(source.cookieHeader(merging: nil, base: "a=auth; b=sess") == "a=auth; b=sess")
        #expect(source.cookieHeader(merging: [], base: "a=auth") == "a=auth")
    }

    // MARK: - Challenge handling

    /// Today's behaviour, pinned before it changes: five blind exchanges, and only
    /// then does anyone ask the UI to solve anything.
    @Test func challengeIsRetriedFiveTimesBeforeAskingForResolution() async throws {
        let transport = ScriptedTransport([.challenge()])
        let resolveCount = Counter()
        let source = Self.dataSource(transport: transport, resolve: {
            await resolveCount.increment()
            throw CloudflareChallengeRequired()
        })

        await #expect(throws: CloudflareChallengeRequired.self) {
            _ = try await source.httpData(from: Self.feedURL, cookies: nil)
        }

        #expect(await transport.requests.count == FAHTTPDataSource.challengeRetries)
        #expect(await resolveCount.value == 1)
    }

    /// The WebView fallback navigates, so it can only ever rescue a GET. A challenged
    /// POST fails instead of being silently replayed as a page load.
    @Test func webViewFallbackRescuesGETButNeverPOST() async throws {
        let fetched = Counter()
        let fetch: FAHTTPDataSource.WebViewFetch = { _ in
            await fetched.increment()
            return Data("<html>rescued</html>".utf8)
        }

        let getSource = Self.dataSource(
            transport: ScriptedTransport([.challenge()]), webViewFetch: fetch
        )
        let rescued = try await getSource.httpData(from: Self.feedURL, cookies: nil)
        #expect(String(data: rescued, encoding: .utf8) == "<html>rescued</html>")
        #expect(await fetched.value == 1)

        let postSource = Self.dataSource(
            transport: ScriptedTransport([.challenge()]), webViewFetch: fetch
        )
        await #expect(throws: CloudflareChallengeRequired.self) {
            _ = try await postSource.httpData(
                from: Self.feedURL, cookies: nil, method: .POST,
                parameters: [URLQueryItem(name: "k", value: "v")]
            )
        }
        #expect(await fetched.value == 1)
    }

    @Test func nonSuccessStatusThrows() async throws {
        let transport = ScriptedTransport([
            FANativeHTTPResponse(statusCode: 500, headers: [:], body: Data(), networkProtocol: "http/1.1")
        ])
        await #expect(throws: FAHTTPError.self) {
            _ = try await Self.dataSource(transport: transport).httpData(from: Self.feedURL, cookies: nil)
        }
    }

    // MARK: - The URLSession fallback

    /// With no transport installed the exchange still goes through URLSession — so
    /// the fallback can't be quietly deleted once the native transport lands. A port
    /// nothing listens on keeps it hermetic: only a real connection attempt can
    /// produce `URLError`, and it is refused immediately.
    @Test func noTransportStillGoesThroughURLSession() async throws {
        let source = FAHTTPDataSource(userAgent: "TestAgent/1.0", cookieHeader: "a=auth")
        await #expect(throws: URLError.self) {
            _ = try await source.httpData(from: URL(string: "http://127.0.0.1:1/")!, cookies: nil)
        }
    }
}

/// `Int` behind an actor, for counting calls made from `@Sendable` closures.
actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
