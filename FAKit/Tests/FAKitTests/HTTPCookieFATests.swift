//
//  HTTPCookieFATests.swift
//  FAKitTests
//
//  Created by Ceylo on 31/05/2026.
//

import Testing
import Foundation
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

    @Test func normalizedClearancePreservesEssentialsAndDropsSameSite() {
        // HTTPCookie itself clamps far-future expiry, so compare the normalized
        // cookie against the original's resolved expiry rather than the raw input.
        let original = HTTPCookie(properties: [
            .name: "cf_clearance",
            .value: "abc123",
            .domain: ".furaffinity.net",
            .path: "/",
            .secure: true,
            .expires: Date(timeIntervalSinceNow: 3600),
            .sameSitePolicy: HTTPCookieStringPolicy.sameSiteStrict,
        ])!

        let normalized = original.normalizedForSharedStorage
        #expect(normalized.name == "cf_clearance")
        #expect(normalized.value == "abc123")
        #expect(normalized.domain == ".furaffinity.net")
        #expect(normalized.path == "/")
        #expect(normalized.isSecure)
        #expect(normalized.expiresDate == original.expiresDate)
        // The rebuild also drops SameSite. Not the causal attribute on iOS 27
        // (the CHIPS StoragePartition key is; see HTTPCookie+FA.swift), but there's
        // no public property key to synthesize a partitioned cookie here, so this
        // asserts the observable part of the rebuild.
        #expect(normalized.sameSitePolicy == nil)
    }

    @Test func normalizedClearanceReplaysFromStorageForFAURL() {
        let storage = HTTPCookieStorage.sharedCookieStorage(
            forGroupContainerIdentifier: "test.cf.normalize.\(UUID().uuidString)"
        )
        for stale in storage.cookies ?? [] { storage.deleteCookie(stale) }

        let original = HTTPCookie(properties: [
            .name: "cf_clearance",
            .value: "xyz789",
            .domain: ".furaffinity.net",
            .path: "/",
            .secure: true,
            .sameSitePolicy: HTTPCookieStringPolicy.sameSiteStrict,
        ])!

        storage.setCookie(original.normalizedForSharedStorage)
        let returned = storage.cookies(for: FAURLs.homeUrl) ?? []
        #expect(returned.contains { $0.name == "cf_clearance" && $0.value == "xyz789" })
    }
}
