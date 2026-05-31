//
//  HTTPCookieFATests.swift
//  FAKitTests
//
//  Created by Ceylo on 31/05/2026.
//

import Testing
import Foundation
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
}
