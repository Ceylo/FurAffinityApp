//
//  FASubmissionsPage.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import Foundation
import SwiftSoup

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
    
    public let submissions: [Submission?]
    public let nextPageUrl: URL?
    public let previousPageUrl: URL?
}

extension FASubmissionsPage {
    public init?(data: Data, baseUri: URL) async {
        let state = signposter.beginInterval("All Submission Previews Parsing")
        defer { signposter.endInterval("All Submission Previews Parsing", state) }
        
        do {
            let string = try String(data: data, encoding: .utf8).unwrap()
            let doc = try SwiftSoup.parse(string, baseUri.absoluteString)
            
            let itemsQuery = "body div#main-window div#site-content form div#messagecenter-new-submissions div#standardpage section div.section-body div#messages-comments-submission div#messagecenter-submissions section figure"
            let items = try doc.select(itemsQuery).array()
            
            async let submissions = items.parallelMap { Submission($0) }
            let buttonsQuery = "body div#main-window div#site-content form div#messagecenter-new-submissions div#standardpage section div.section-body div.aligncenter a"
            let buttonItems = try doc.select(buttonsQuery).array()
            let prevButton = try buttonItems.first { try $0.text().starts(with: "Prev") }
            let nextButton = try buttonItems.first { try $0.text().starts(with: "Next") }
            
            if let prevButton = prevButton,
               let href = try? prevButton.attr("href") {
                self.previousPageUrl = try URL(unsafeString: FAURLs.homeUrl.absoluteString + href)
            } else {
                self.previousPageUrl = nil
            }
            
            if let nextButton = nextButton,
               let href = try? nextButton.attr("href") {
                self.nextPageUrl = try URL(unsafeString: FAURLs.homeUrl.absoluteString + href)
            } else {
                self.nextPageUrl = nil
            }
            
            self.submissions = await submissions
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            return nil
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
            self.url = FAURLs.submissionUrl(sid: sid)
            
            let thumbNodes = try node.select("figure b u a img")
            let thumbSrc = try thumbNodes.first().unwrap().attr("src")
            let thumbWidthStr = try thumbNodes.first().unwrap().attr("data-width")
            let thumbHeightStr = try thumbNodes.first().unwrap().attr("data-height")
            let thumbWidth = try Float(thumbWidthStr).unwrap()
            let thumbHeight = try Float(thumbHeightStr).unwrap()
            self.thumbnailUrl = try URL(unsafeString: "https:\(thumbSrc)")
            self.thumbnailWidthOnHeightRatio = thumbWidth / thumbHeight
            
            let captionNodes = try node.select("figcaption p a")
            guard captionNodes.count >= 2 else {
                logger.error("\(#file, privacy: .public) - invalid structure")
                return nil
            }
            self.title = try captionNodes[0].text()
            self.author = try captionNodes[1].attr("href")
                .substring(matching: "/user/(.+)/")!
            self.displayAuthor = try captionNodes[1].text()
        } catch {
            return nil
        }
    }
}
