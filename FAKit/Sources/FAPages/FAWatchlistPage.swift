//
//  FAWatchlistPage.swift
//  FAKit
//
//  Created by Ceylo on 02/09/2024.
//

@preconcurrency import SwiftSoup
import Foundation

public struct FAWatchlistPage: Equatable, Sendable {
    public struct User: Equatable, Sendable, Identifiable {
        public init(name: String, displayName: String) {
            self.name = name
            self.displayName = displayName
        }
        
        public let name: String
        public let displayName: String
        
        public var id: String { name }
    }
    
    public enum WatchDirection: Sendable {
        case watching
        case watchedBy
    }
    
    public let currentUser: User
    public let watchDirection: WatchDirection
    public let users: [User]
    public let nextPageUrl: URL?
}

extension FAWatchlistPage {
    public init?(data: Data, baseUri: URL) {
        let state = signposter.beginInterval("Watchlist Parsing")
        defer { signposter.endInterval("Watchlist Parsing", state) }
        
        do {
            let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
            let items = try doc.select("div.watch-list-items")
            let users = items
                .map { User($0) }
                .compactMap { $0 }
            
            // As of 6th September 2025
            // When there's a next page:
            // <form method="get" action="/watchlist/to/username">
            //     <input type="hidden" name="page" value="2">
            //     <button class="button" type="submit">Next 200</button>
            // </form>
            
            // When there's not:
            // <form method="get" action="/watchlist/to/username">
            //     <input type="hidden" name="page" value="12">
            //     <button class="button" type="submit" disabled="">Next 200</button>
            // </form>
            let nextPageFormNode = try doc
                .select("div.section-footer > div.floatright > form")
            let nextPageRelativeLink = try nextPageFormNode.attr("action")
            let nextPageNumberStr = try nextPageFormNode.select("input[name=\"page\"]").attr("value")
            let nextPageButtonDisabled = try nextPageFormNode.select("button[type=\"submit\"]").hasAttr("disabled")
            
            let nextPageUrl: URL? = if nextPageButtonDisabled {
                nil
            } else {
                // https://www.furaffinity.net/watchlist/to/username?page=12
                try URL(unsafeString: FAURLs.homeUrl.absoluteString + nextPageRelativeLink)
                    .appending(queryItems: [.init(name: "page", value: nextPageNumberStr)])
            }
            
            let (username, _, watchDirection) = try FAURLs.parseWatchlistUrl(baseUri).unwrap()
            
            let title = try doc.select("div#main-window > div#site-content > section > div.section-header > h2").text()
            let displayName = switch watchDirection {
            case .watchedBy:
                try title.substring(matching: "Users that are watching (.+)").unwrap()
            case .watching:
                try title.substring(matching: "Users (.+) is watching").unwrap()
            }
            
            self.init(
                currentUser: .init(name: username, displayName: displayName),
                watchDirection: watchDirection,
                users: users,
                nextPageUrl: nextPageUrl
            )
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            return nil
        }
    }
}

extension FAWatchlistPage.User {
    init?(_ node: SwiftSoup.Element) {
        let state = signposter.beginInterval("Watchlist User Parsing")
        defer { signposter.endInterval("Watchlist User Parsing", state) }
        
        do {
            let linkNode = try node.select("a")
            let name = try linkNode
                .attr("href")
                .substring(matching: "\\/user\\/(.+)\\/")
                .unwrap()
            let displayName = try linkNode.text()
            
            self.init(name: name, displayName: displayName)
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            return nil
        }
    }
}
