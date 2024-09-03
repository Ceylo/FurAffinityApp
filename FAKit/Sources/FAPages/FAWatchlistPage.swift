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
    public init?(data: Data, baseUri: URL) async {
        let state = signposter.beginInterval("Watchlist Parsing")
        defer { signposter.endInterval("Watchlist Parsing", state) }
        
        do {
            let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
            let items = try doc.select("div.watch-list-items")
            let users = await items
                .parallelMap { User($0) }
                .compactMap { $0 }
            
            let nextPageRelLink = try doc
                .select("div.section-footer > div.floatright > form")
                .attr("action")
            
            let nextPageUrl: URL? = if !baseUri.absoluteString.contains(nextPageRelLink) {
                try URL(unsafeString: FAURLs.homeUrl.absoluteString + nextPageRelLink)
            } else {
                nil
            }
            
            let (username, watchDirection) = try FAURLs.parseWatchlistUrl(baseUri).unwrap()
            
            let title = try doc.select("body > div > section > div.section-header > h2").text()
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
