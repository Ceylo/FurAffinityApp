//
//  HTTPCookieFATests.swift
//  FAKitTests
//
//  Created by Ceylo on 31/05/2026.
//

import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import FAPages
@testable import FAKit

struct HTTPCookieFATests {
    private func cookie(name: String, domain: String) -> HTTPCookie {
        HTTPCookie(properties: [
            .name: name,
            .value: "v",
            .domain: domain,
            .path: "/",
        ])!
    }

    @Test func returnsOnlyFADomainNonClearanceCookies() {
        let cookies = [
            cookie(name: "cf_clearance", domain: ".furaffinity.net"),
            cookie(name: "a", domain: "www.furaffinity.net"),
            cookie(name: "b", domain: ".furaffinity.net"),
            cookie(name: "other", domain: "example.com"),
        ]
        #expect(cookies.faAuthCookies.map(\.name).sorted() == ["a", "b"])
    }

    @Test func emptyInputReturnsEmpty() {
        #expect([HTTPCookie]().faAuthCookies.isEmpty)
    }

    @Test func onlyClearanceReturnsEmpty() {
        let cookies = [cookie(name: "cf_clearance", domain: ".furaffinity.net")]
        #expect(cookies.faAuthCookies.isEmpty)
    }

    /// A secure `cf_clearance` for `.furaffinity.net`, SameSite=Strict where the
    /// platform has the attribute: corelibs Foundation has no `sameSitePolicy`.
    private func clearance(value: String, expires: Date? = nil) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: "cf_clearance",
            .value: value,
            .domain: ".furaffinity.net",
            .path: "/",
            .secure: "TRUE",
        ]
        if let expires {
            properties[.expires] = expires
        }
        #if !os(Android)
        properties[.sameSitePolicy] = HTTPCookieStringPolicy.sameSiteStrict
        #endif
        return HTTPCookie(properties: properties)!
    }

    @Test func normalizedClearancePreservesEssentialsAndDropsSameSite() {
        // HTTPCookie itself clamps far-future expiry, so compare the normalized
        // cookie against the original's resolved expiry rather than the raw input.
        let original = clearance(value: "abc123", expires: Date(timeIntervalSinceNow: 3600))

        let normalized = original.normalizedForSharedStorage
        #expect(normalized.name == "cf_clearance")
        #expect(normalized.value == "abc123")
        #expect(normalized.domain == ".furaffinity.net")
        #expect(normalized.path == "/")
        #expect(normalized.isSecure)
        #expect(normalized.expiresDate == original.expiresDate)
        #if !os(Android)
        // The rebuild also drops SameSite. Not the causal attribute on iOS 27
        // (the CHIPS StoragePartition key is; see HTTPCookie+FA.swift), but there's
        // no public property key to synthesize a partitioned cookie here, so this
        // asserts the observable part of the rebuild.
        #expect(normalized.sameSitePolicy == nil)
        #endif
    }

    // What WebCookie.asHTTPCookie builds on Android, where WebCookie itself needs
    // a JVM and so cannot be made in a test.
    @Test func plainCookieKeepsItsSecureFlag() throws {
        let cookie = try #require(HTTPCookie.plain(
            name: "a", value: "v", domain: ".furaffinity.net", path: "/",
            expires: nil, isSecure: true
        ))
        #expect(cookie.isSecure)
    }

    @Test func normalizedClearanceReplaysFromStorageForFAURL() {
        let storage = HTTPCookieStorage.sharedCookieStorage(
            forGroupContainerIdentifier: "test.cf.normalize.\(UUID().uuidString)"
        )
        for stale in storage.cookies ?? [] { storage.deleteCookie(stale) }

        storage.setCookie(clearance(value: "xyz789").normalizedForSharedStorage)
        let returned = storage.cookies(for: FAURLs.homeUrl) ?? []
        #expect(returned.contains { $0.name == "cf_clearance" && $0.value == "xyz789" })
    }
}
