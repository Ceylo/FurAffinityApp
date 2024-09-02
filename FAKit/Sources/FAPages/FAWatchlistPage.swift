//
//  FAWatchlistPage.swift
//  FAKit
//
//  Created by Ceylo on 02/09/2024.
//

@preconcurrency import SwiftSoup
import Foundation

struct FAWatchlistPage: Equatable {
    struct FAUser: Equatable {
        let name: String
        let displayName: String
    }
    
    let users: [FAUser]
    let nextPageUrl: URL?
}

extension FAWatchlistPage {
    public init?(data: Data, baseUri: URL) async {
        let state = signposter.beginInterval("Watchlist Parsing")
        defer { signposter.endInterval("Watchlist Parsing", state) }
        
        do {
            let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
            let items = try doc.select("div.watch-list-items")
            let users = await items
                .parallelMap { FAUser($0) }
                .compactMap { $0 }
            
            let nextPageRelLink = try doc
                .select("div.section-footer > div.floatright > form")
                .attr("action")
            
            let nextPageUrl: URL? = if !baseUri.absoluteString.contains(nextPageRelLink) {
                try URL(unsafeString: FAURLs.homeUrl.absoluteString + nextPageRelLink)
            } else {
                nil
            }
            
            self.init(users: users, nextPageUrl: nextPageUrl)
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            return nil
        }
    }
}

extension FAWatchlistPage.FAUser {
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
