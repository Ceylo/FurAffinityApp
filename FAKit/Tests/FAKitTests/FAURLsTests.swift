//
//  FAURLsTests.swift
//  FAKit
//
//  Created by Ceylo on 13/09/2024.
//

import Testing
import Foundation
@testable import FAPages

struct FAURLsTests {
    @Test("usernameFromUserUrl", arguments: [
        ("https://www.furaffinity.net/", nil),
        ("https://www.furaffinity.net/view/123456/", nil),
        ("https://www.furaffinity.net/user/", nil),
        ("https://www.furaffinity.net/user/foo", "foo"),
        ("https://www.furaffinity.net/user/foo/", "foo"),
        ("https://www.furaffinity.net/user/foo#shout-123456", "foo"),
        ("https://www.furaffinity.net/user/foo#shout-123456/", "foo")
    ]) func usernameFromUserUrl(url: String, username: String?) async throws {
        let url = try URL(string: url).unwrap()
        #expect(FAURLs.usernameFrom(userUrl: url) == username)
    }
    
    @Test("avatarFromUrl", arguments: [
        ("", nil),
        ("foo", "https://a.furaffinity.net/20240920/foo.gif"),
        ("^6", "https://a.furaffinity.net/20240920/%5E6.gif")
    ])
    func avatarFromUrl(username: String, expectedUrl: String?) async throws {
        let date = try Date("2024-09-20T11:11:11Z", strategy: .iso8601)
        let url = FAURLs.avatarUrl(for: username, date: date)
        #expect(url?.absoluteString == expectedUrl)
    }
}
