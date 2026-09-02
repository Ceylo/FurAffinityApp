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

    private func repair(observed: UInt64) -> FAConnectionRepairResult {
        calls.append(.repair(observed: observed))
        guard CloudflareConnectionRepair.shouldEvict(observed: observed, current: epoch) else {
            return FAConnectionRepairResult(didEvict: false, evictedConnections: 0, epoch: epoch)
        }
        epoch += 1
        return FAConnectionRepairResult(didEvict: true, evictedConnections: 1, epoch: epoch)
    }

    nonisolated var transport: FANativeTransport {
        FANativeTransport(
            perform: { await self.perform($0) },
            repairConnections: { await self.repair(observed: $0) }
        )
    }
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

    /// A challenge is repaired, not waited out. Under h2 the very first one asks —
    /// a retry there would ride the same poisoned connection, which is how the
    /// earlier h2 arm reached 100% 403. Under h1 the challenge carries
    /// `Connection: close`, so exactly one blind redraw is a genuinely fresh
    /// verdict and is worth taking first.
    @Test(arguments: [("h2", 1), ("http/1.1", 2), ("urlsession", 2)])
    func blindRedrawsAreProtocolConditional(networkProtocol: String, expectedExchanges: Int) async throws {
        let transport = ScriptedTransport([.challenge(protocol: networkProtocol)])
        let resolveCount = Counter()
        let source = Self.dataSource(transport: transport, resolve: {
            await resolveCount.increment()
            throw CloudflareChallengeRequired()
        })

        await #expect(throws: CloudflareChallengeRequired.self) {
            _ = try await source.httpData(from: Self.feedURL, cookies: nil)
        }

        #expect(await transport.requests.count == expectedExchanges)
        #expect(await resolveCount.value == 1)
    }

    /// Evict, solve, evict again, redial — in that order. Evicting *before* the
    /// solve is what keeps other workers off the poisoned connection during the
    /// 1.5–25 s it takes; evicting again after is what drops the connection some
    /// other worker opened with the old clearance while we waited.
    @Test func repairEvictsBeforeAndAfterResolution() async throws {
        let transport = ScriptedTransport([.challenge(protocol: "h2"), .ok()], epoch: 4)
        let source = Self.dataSource(transport: transport, resolve: {})

        _ = try await source.httpData(from: Self.feedURL, cookies: nil)

        #expect(await transport.calls == [
            .perform,
            .repair(observed: 4),   // the epoch the challenged exchange was issued against
            .repair(observed: 5),   // …and the one the first repair produced
            .perform,
        ])
    }

    /// The redial must carry the clearance the solve just minted, not the one that
    /// was challenged. Nothing in `repairAndResolve` re-reads the jar itself — it
    /// relies on `awaitResolution()` returning only after the refresh — so this is
    /// the test that keeps that invariant honest.
    @Test func retryCarriesTheRefreshedClearance() async throws {
        let clearance = Latch("a=auth; cf_clearance=STALE000")
        let transport = ScriptedTransport([.challenge(protocol: "h2"), .ok()])
        let source = FAHTTPDataSource(
            userAgent: "TestAgent/1.0",
            cookieHeader: "a=auth; cf_clearance=STALE000",
            liveCookieHeader: { await clearance.value },
            nativeTransport: transport.transport,
            awaitChallengeResolution: { await clearance.set("a=auth; cf_clearance=FRESH111") }
        )

        _ = try await source.httpData(from: Self.feedURL, cookies: nil)

        let sent = await transport.requests.map(\.cookieHeader)
        #expect(sent == ["a=auth; cf_clearance=STALE000", "a=auth; cf_clearance=FRESH111"])
    }

    /// Exactly one retry after a repair. A second failure means the solve didn't
    /// produce a passing connection, and the right next move is a different
    /// mechanism, not another sample of the same one.
    @Test func onePostRepairRetryThenTheWebViewFallback() async throws {
        let transport = ScriptedTransport([.challenge(protocol: "h2")])
        let fetched = Counter()
        let source = Self.dataSource(
            transport: transport,
            webViewFetch: { _ in
                await fetched.increment()
                return Data("<html>rescued</html>".utf8)
            },
            resolve: {}
        )

        let rescued = try await source.httpData(from: Self.feedURL, cookies: nil)

        #expect(String(data: rescued, encoding: .utf8) == "<html>rescued</html>")
        #expect(await transport.requests.count == 2)   // the challenged one, and one redial
        #expect(await fetched.value == 1)
    }

    /// With no transport installed the repair is a no-op that leaves the epoch
    /// alone — so the ordering above lands and is measurable before any OkHttp
    /// exists.
    @Test func repairIsANoOpWithoutATransport() async throws {
        let resolved = Counter()
        let source = FAHTTPDataSource(
            userAgent: "TestAgent/1.0",
            cookieHeader: "a=auth",
            awaitChallengeResolution: { await resolved.increment() }
        )
        await #expect(throws: URLError.self) {
            _ = try await source.httpData(from: URL(string: "http://127.0.0.1:1/")!, cookies: nil)
        }
        // A refused connection is not a challenge, so nothing was repaired.
        #expect(await resolved.value == 0)
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
            transport: ScriptedTransport([.challenge(protocol: "h2")]), webViewFetch: fetch
        )
        let rescued = try await getSource.httpData(from: Self.feedURL, cookies: nil)
        #expect(String(data: rescued, encoding: .utf8) == "<html>rescued</html>")
        #expect(await fetched.value == 1)

        let postSource = Self.dataSource(
            transport: ScriptedTransport([.challenge(protocol: "h2")]), webViewFetch: fetch
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

/// A `String` behind an actor, so a `@Sendable` probe and a `@Sendable` resolver
/// can share one live cookie jar.
actor Latch {
    private(set) var value: String
    init(_ value: String) { self.value = value }
    func set(_ new: String) { value = new }
}

/// `Int` behind an actor, for counting calls made from `@Sendable` closures.
actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
