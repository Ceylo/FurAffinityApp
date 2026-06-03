//
//  FAHomePage.swift
//
//
//  Created by Ceylo on 17/10/2021.
//

import SwiftSoup
import Foundation

public struct FAHomePage: FAPage {
    public let username: String
    public let displayUsername: String
}

extension FAHomePage {
    public init(html: String, url: URL) throws {
        let state = signposter.beginInterval("Home Parsing")
        defer { signposter.endInterval("Home Parsing", state) }
        
        do {
            let doc = try SwiftSoup.parse(html, url.absoluteString)
            
            let usernameQuery = "body div.mobile-navigation div.nav-ac-container article.nav-ac-content div.mobile-nav-content-container div.aligncenter h2 a"
            let element = try doc.select(usernameQuery)
            let link = try element.attr("href")
            
            let username = try link.substring(matching: "/user/(.+)/").unwrap()
            let displayUsername = try element.text()
            
            self.init(
                username: username,
                displayUsername: displayUsername
            )
        } catch {
            logger.error("\(#file) - failed decoding or parsing: \(error)")
            throw error
        }
    }
    
    public init(data: Data, url: URL) throws {
        let html = String(decoding: data, as: UTF8.self)
        try self.init(html: html, url: url)
    }
}
