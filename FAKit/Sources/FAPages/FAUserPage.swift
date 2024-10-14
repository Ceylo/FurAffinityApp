//
//  FAUserPage.swift
//  
//
//  Created by Ceylo on 05/12/2021.
//

@preconcurrency import SwiftSoup
import Foundation

public struct FAUserPage: Equatable {
    public let name: String
    public let displayName: String
    public let bannerUrl: URL
    public let htmlDescription: String
    public let shouts: [FAPageComment]
    
    public struct WatchData: Equatable, Sendable {
        public let watchUrl: URL
        public var watching: Bool {
            watchUrl.path().starts(with: "/unwatch/")
        }
        
        public init(watchUrl: URL) {
            self.watchUrl = watchUrl
        }
    }
    /// Unavailable when parsing your own user page
    public let watchData: WatchData?
}

extension FAUserPage {
    static func parseDisplayName(in string: String) throws -> String {
        try string
            .substring(matching: "(~.+|!.+)").unwrap()
            .trimmingPrefix("~")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    public init?(data: Data) async {
        let state = signposter.beginInterval("User Page Parsing")
        defer { signposter.endInterval("User Page Parsing", state) }
        
        do {
            let doc = try SwiftSoup.parse(String(decoding: data, as: UTF8.self))
            let mainWindowNode = try doc.select("body div#main-window")
            let navHeaderNode = try mainWindowNode.select("div#site-content userpage-nav-header")
            
            let navAvatarNode = try navHeaderNode.select("userpage-nav-avatar a")
            let username = try navAvatarNode
                .attr("href")
                .substring(matching: "\\/user\\/(.+)\\/")
                .unwrap()
            self.name = username
            
            let displayNameQuery = "userpage-nav-user-details h1 username"
            let displayNameNode = try navHeaderNode.select(displayNameQuery).first().unwrap()
            let rawDisplayName = try displayNameNode.text()
            self.displayName = try Self.parseDisplayName(in: rawDisplayName)
            
            let bannerNode = try mainWindowNode.select("div#header a img")
            let bannerStringUrl = try bannerNode.attr("src")
            if bannerStringUrl.starts(with: "//") {
                self.bannerUrl = try URL(unsafeString: "https:" + bannerStringUrl)
            } else {
                self.bannerUrl = FAURLs.homeUrl.appending(path: bannerStringUrl)
            }
            
            let descriptionQuery = "div#site-content div#page-userpage section.userpage-layout-profile div.userpage-layout-profile-container div.userpage-profile"
            let descriptionNode = try mainWindowNode.select(descriptionQuery)
            self.htmlDescription = try descriptionNode.html()
            
            let shoutsQuery = "div#site-content div#page-userpage section.userpage-right-column div.userpage-section-right div.comment_container"
            let shoutsNodes = try mainWindowNode.select(shoutsQuery)
            self.shouts = try await shoutsNodes
                .parallelMap { try FAPageComment($0, type: .shout) }
                .compactMap { $0 }
            
            if let watchButtonNode = try navHeaderNode.select("userpage-nav-interface-buttons a.button").first() {
                let watchLink = try watchButtonNode.attr("href")
                let watchUrl = try URL(string: FAURLs.homeUrl.absoluteString + watchLink).unwrap()
                self.watchData = WatchData(watchUrl: watchUrl)
            } else {
                self.watchData = nil
            }
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            return nil
        }
    }
}
