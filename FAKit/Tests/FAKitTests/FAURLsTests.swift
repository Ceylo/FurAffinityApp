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
        ("foo", "https://a.furaffinity.net/foo.gif"),
        ("^6", "https://a.furaffinity.net/%5E6.gif")
    ])
    func avatarFromUrl(username: String, expectedUrl: String?) async throws {
        let url = FAURLs.avatarUrl(for: username)
        #expect(url?.absoluteString == expectedUrl)
    }
    
    @Test(arguments: [
        ("https://www.furaffinity.net/watchlist/by/username", "username", 1, FAWatchlistPage.WatchDirection.watching),
        ("https://www.furaffinity.net/watchlist/by/username/", "username", 1, .watching),
        ("https://www.furaffinity.net/watchlist/by/username/1", "username", 1, .watching),
        ("https://www.furaffinity.net/watchlist/by/username/1/", "username", 1, .watching),
        ("https://www.furaffinity.net/watchlist/by/username?page=1", "username", 1, .watching),
        ("https://www.furaffinity.net/watchlist/to/username?page=2", "username", 2, .watchedBy),
        // Old URL format,
        ("https://www.furaffinity.net/watchlist/to/username/2", "username", 2, .watchedBy),
        ("https://www.furaffinity.net/watchlist/to/username/2/", "username", 2, .watchedBy),
    ])
    func parseWatchlistUrl(
        urlStr: String,
        expectedUsername: String,
        expectedPage: Int,
        expectedWatchDirection: FAWatchlistPage.WatchDirection
    ) throws {
        let parsed = try FAURLs.parseWatchlistUrl(URL(string: urlStr)!).unwrap()
        #expect(parsed.username == expectedUsername)
        #expect(parsed.page == expectedPage)
        #expect(parsed.watchDirection == expectedWatchDirection)
    }
}
