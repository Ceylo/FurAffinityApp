//
//  FASubmissionsPage.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import Foundation
import SwiftSoup
import Regex

public struct FASubmissionsPage {
    public struct Submission: Equatable {
        public init(sid: Int, url: URL, thumbnailUrl: URL, thumbnailWidthOnHeightRatio: Float, title: String, author: String, displayAuthor: String) {
            self.sid = sid
            self.url = url
            self.thumbnailUrl = thumbnailUrl
            self.thumbnailWidthOnHeightRatio = thumbnailWidthOnHeightRatio
            self.title = title
            self.author = author
            self.displayAuthor = displayAuthor
        }
        
        public let sid: Int
        public let url: URL
        public let thumbnailUrl: URL
        public let thumbnailWidthOnHeightRatio: Float
        public let title: String
        public let author: String
        public let displayAuthor: String
    }
    
    static public let url = URL(string: "https://www.furaffinity.net/msg/submissions/")!
    public let submissions: [Submission?]
    public let nextPageUrl: URL?
    public let previousPageUrl: URL?
}

extension FASubmissionsPage {
    public init?(data: Data) {
        let state = signposter.beginInterval("All Submission Previews Parsing")
        defer { signposter.endInterval("All Submission Previews Parsing", state) }
        
        guard let string = String(data: data, encoding: .utf8),
              let doc = try? SwiftSoup.parse(string, Self.url.absoluteString)
        else {
            return nil
        }
        
        let itemsQuery = "body div#main-window div#site-content form div#messagecenter-new-submissions div#standardpage section div.section-body div#messages-comments-submission div#messagecenter-submissions section figure"
        guard let items = try? doc.select(itemsQuery).array() else {
            return nil
        }
        
        self.submissions = items
            .map { Submission($0) }
        
        let buttonsQuery = "body div#main-window div#site-content form div#messagecenter-new-submissions div#standardpage section div.section-body div.aligncenter a"
        guard let buttonItems = try? doc.select(buttonsQuery).array() else {
            return nil
        }
        
        let prevButton = try? buttonItems.first { try $0.text().starts(with: "Prev") }
        let nextButton = try? buttonItems.first { try $0.text().starts(with: "Next") }
        
        if let prevButton = prevButton,
           let href = try? prevButton.attr("href") {
            self.previousPageUrl = URL(string: "https://www.furaffinity.net" + href)
        } else {
            self.previousPageUrl = nil
        }
        
        if let nextButton = nextButton,
           let href = try? nextButton.attr("href") {
            self.nextPageUrl = URL(string: "https://www.furaffinity.net" + href)
        } else {
            self.nextPageUrl = nil
        }
    }
}

extension FASubmissionsPage.Submission {
    init?(_ node: SwiftSoup.Element) {
        let state = signposter.beginInterval("Submission Preview Parsing")
        defer { signposter.endInterval("Submission Preview Parsing", state) }
        
        do {
            let sidStr = try node.attr("id")
            guard sidStr.hasPrefix("sid-") else { return nil }
            let index = sidStr.index(sidStr.startIndex, offsetBy: 4)
            let sid = Int(String(sidStr[index...]))!
            self.sid = sid
            self.url = URL(string: "https://www.furaffinity.net/view/\(sid)/")!
            
            let thumbNodes = try node.select("figure b u a img")
            guard let thumbSrc = try thumbNodes.first()?.attr("src"),
                  let thumbWidthStr = try thumbNodes.first()?.attr("data-width"),
                  let thumbHeightStr = try thumbNodes.first()?.attr("data-height"),
                  let thumbWidth = Float(thumbWidthStr),
                  let thumbHeight = Float(thumbHeightStr)
            else { return nil }
            self.thumbnailUrl = URL(string: "https:\(thumbSrc)")!
            self.thumbnailWidthOnHeightRatio = thumbWidth / thumbHeight
            
            let captionNodes = try node.select("figure figcaption label p a")
            guard captionNodes.count >= 2 else { return nil }
            self.title = try captionNodes[0].text()
            self.author = try captionNodes[1].attr("href")
                .substring(matching: "/user/(.+)/")!
            self.displayAuthor = try captionNodes[1].text()
        } catch {
            return nil
        }
    }
}
