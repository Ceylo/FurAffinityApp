//
//  FAURLs.swift
//  
//
//  Created by Ceylo on 28/10/2023.
//

import Foundation

public enum FAURLs {
    public static let domain = "furaffinity.net"
    public static let homeUrl = URL(string: "https://www.furaffinity.net")!
    public static let signupUrl = URL(string: "https://www.furaffinity.net/register")!
    
    public static let submissionsUrl = URL(
        string: "https://www.furaffinity.net/msg/submissions/"
    )!
    
    public static let latest72SubmissionsUrl = submissionsUrl.appending(path: "new@72")
    public static func submissionsUrl(from sid: Int) -> URL {
        submissionsUrl.appending(component: "new~\(sid)@72")
    }
    
    public static let notesInboxUrl = URL(
        string: "https://www.furaffinity.net/controls/switchbox/inbox/"
    )!
    
    public static let notesSentUrl = URL(
        string: "https://www.furaffinity.net/controls/switchbox/sent/"
    )!
    
    public static let notesArchiveUrl = URL(
        string: "https://www.furaffinity.net/controls/switchbox/archive/"
    )!
    
    public static let notesTrashUrl = URL(
        string: "https://www.furaffinity.net/controls/switchbox/trash/"
    )!
    
    public static let notificationsUrl = URL(
        string: "https://www.furaffinity.net/msg/others/"
    )!
    
    public static func userpageUrl(for username: String) throws -> URL {
        guard !username.isEmpty else {
            throw FAPagesError.invalidParameter
        }
        return try URL(unsafeString: "https://www.furaffinity.net/user/\(username)/")
    }
    
    public static func avatarUrl(for username: String) -> URL? {
        guard !username.isEmpty else {
            return nil
        }
        
        let str = "https://a.furaffinity.net/\(username).gif"
        return try? URL(unsafeString: str)
    }
    
    public static func newNoteUrl(for username: String) -> URL? {
        guard !username.isEmpty else {
            return nil
        }
        return try? URL(unsafeString: "https://www.furaffinity.net/newpm/\(username)/")
    }
    
    public static func usernameFrom(userUrl: URL) -> String? {
        var urlString = userUrl.absoluteString
        if urlString.suffix(1) != "/" {
            urlString.append("/")
        }
        
        guard urlString.wholeMatch(of: /https:\/\/www\.furaffinity\.net\/user\/.+\//) != nil else {
            return nil
        }
        
        return userUrl.lastPathComponent
    }
    
    public static func galleryUrl(for username: String) -> URL {
        URL(string: "https://www.furaffinity.net/gallery/\(username)/")!
    }
    
    public static func favoritesUrl(for username: String) -> URL {
        URL(string: "https://www.furaffinity.net/favorites/\(username)/")!
    }
    
    public static func journalsUrl(for username: String) -> URL {
        URL(string: "https://www.furaffinity.net/journals/\(username)/")!
    }
    
    public static func watchlistUrl(for username: String, page: Int, direction: FAWatchlistPage.WatchDirection) -> URL {
        switch direction {
        case .watchedBy:
            URL(string: "https://www.furaffinity.net/watchlist/to/\(username)")!
                .appending(queryItems: [.init(name: "page", value: "\(page)")])
        case .watching:
            URL(string: "https://www.furaffinity.net/watchlist/by/\(username)")!
                .appending(queryItems: [.init(name: "page", value: "\(page)")])
        }
    }
    
    public static func parseWatchlistUrl(_ url: URL) -> (username: String, page: Int, watchDirection: FAWatchlistPage.WatchDirection)? {
        do {
            // https://www.furaffinity.net/watchlist/to/xxx
            // https://www.furaffinity.net/watchlist/by/xxx
            // https://www.furaffinity.net/watchlist/by/xxx?page=n
            // https://www.furaffinity.net/watchlist/by/xxx/n/
            let components = url.pathComponents
            guard components.count >= 4 else {
                logger.warning("\(url) not recognized as a watchlist url, expected at least 4 components but got \(components.count)")
                return nil
            }
            
            guard components[1] == "watchlist" else {
                logger.warning("\(url) not recognized as a watchlist url, expected /watchlist/ but got \(components[1])")
                return nil
            }
            
            let direction = components[2]
            let username = components[3]
            
            let queryItems = try URLComponents(url: url, resolvingAgainstBaseURL: false)
                .unwrap()
                .queryItems
            
            let pageNumber: Int
            if let pageQueryItem = queryItems?.first(where: { $0.name == "page" }) {
                pageNumber = pageQueryItem.value.flatMap { Int($0) } ?? 1
            } else if components.count >= 5, let number = Int(components[4]) {
                pageNumber = number
            } else {
                pageNumber = 1
            }
            
            let watchDirection: FAWatchlistPage.WatchDirection
            switch direction {
            case "to":
                watchDirection = .watchedBy
            case "by":
                watchDirection = .watching
            default:
                logger.error("\(#file) - invalid direction in url: \(direction)")
                return nil
            }
            
            return (username, pageNumber, watchDirection)
        } catch {
            logger.error("\(#file) - \(error)")
            return nil
        }
    }
    
    public static let searchUrl = URL(string: "https://www.furaffinity.net/search/")!

    /// Builds the `GET /search/` URL for `query`. Checked checkboxes are emitted
    /// as `rating-general=1`, `type-art=1`, …; radios/selects as `range=…`,
    /// `order-by=…`, etc. Enums are iterated in `CaseIterable` order so the
    /// produced query string is deterministic (and testable).
    ///
    /// Gender has no form param: the site appends the selected values to the `q`
    /// text as an `@keywords male female …` operator, so we do the same.
    public static func searchUrl(for query: FASearchQuery) -> URL {
        var items: [URLQueryItem] = [
            .init(name: "q", value: searchQueryText(for: query)),
            .init(name: "order-by", value: query.sortOrder.rawValue),
            .init(name: "order-direction", value: query.sortDirection.rawValue),
            .init(name: "range", value: query.dateRange.rawValue),
        ]

        for rating in Rating.allCases where query.ratings.contains(rating) {
            items.append(.init(name: "rating-\(rating.searchParamSuffix)", value: "1"))
        }

        for type in FASearchQuery.ContentType.allCases where query.contentTypes.contains(type) {
            items.append(.init(name: "type-\(type.rawValue)", value: "1"))
        }

        items.append(.init(name: "mode", value: query.matchMode.rawValue))
        items.append(.init(name: "page", value: "\(query.page)"))
        items.append(.init(name: "perpage", value: "72"))

        return searchUrl.appending(queryItems: items)
    }

    /// The `q` value: the user's text, with any selected genders folded in as an
    /// `@keywords male female …` operator (matching what the site's JS produces).
    private static func searchQueryText(for query: FASearchQuery) -> String {
        guard !query.genders.isEmpty else { return query.text }

        let genderTokens = FASearchQuery.Gender.allCases
            .filter { query.genders.contains($0) }
            .map(\.rawValue)
            .joined(separator: " ")
        let keywords = "@keywords \(genderTokens)"
        return query.text.isEmpty ? keywords : "\(query.text) \(keywords)"
    }

    public static func submissionUrl(sid: Int) -> URL {
        URL(string: "https://www.furaffinity.net/view/\(sid)/")!
    }
    
    public static func journalUrl(jid: Int) -> URL {
        URL(string: "https://www.furaffinity.net/journal/\(jid)/")!
    }
}
