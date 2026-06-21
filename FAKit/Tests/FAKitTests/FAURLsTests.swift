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

    @Test
    func searchUrl_defaultQuery() throws {
        let url = FAURLs.searchUrl(for: .default)
        #expect(url.absoluteString == "https://www.furaffinity.net/search/?"
            + "q=&order-by=relevancy&order-direction=desc&range=5years"
            + "&rating-general=1&rating-mature=1&rating-adult=1"
            + "&type-art=1&type-music=1&type-flash=1&type-story=1&type-photo=1&type-poetry=1"
            + "&mode=extended&page=1&perpage=72")
    }

    @Test
    func searchUrl_populatedQuery() throws {
        let query = FASearchQuery(
            text: "wolf",
            sortOrder: .date,
            sortDirection: .ascending,
            dateRange: .thirtyDays,
            ratings: [.general],
            contentTypes: [.art, .music],
            genders: [.male],
            matchMode: .any,
            page: 3
        )
        let items = try queryItems(of: FAURLs.searchUrl(for: query))
        // A selected gender folds into q as an @keywords operator.
        #expect(items["q"] == "wolf @keywords male")
        #expect(items["order-by"] == "date")
        #expect(items["order-direction"] == "asc")
        #expect(items["range"] == "30days")
        #expect(items["rating-general"] == "1")
        #expect(items["type-art"] == "1")
        #expect(items["type-music"] == "1")
        #expect(items["mode"] == "any")
        #expect(items["page"] == "3")
        #expect(items["perpage"] == "72")
    }

    @Test
    func searchUrl_allGendersAppendKeywords() throws {
        var query = FASearchQuery.default
        query.genders = Set(FASearchQuery.Gender.allCases)
        let items = try queryItems(of: FAURLs.searchUrl(for: query))
        // Matches the q produced by the site when every gender box is checked.
        #expect(items["q"] == "@keywords male female trans_male trans_female intersex non_binary")
    }

    private func queryItems(of url: URL) throws -> [String: String] {
        let components = try URLComponents(url: url, resolvingAgainstBaseURL: false).unwrap()
        return Dictionary(
            (components.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
