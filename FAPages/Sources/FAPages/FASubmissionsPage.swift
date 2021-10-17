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
        public let sid: Int
        public let url: URL
        public let thumbnailUrl: URL
        public let title: String
        public let author: String
        public let displayAuthor: String
    }
    
    public let submissions: [Submission?]
    public let nextPageUrl: URL?
    public let previousPageUrl: URL?
}

extension FASubmissionsPage {
    public init?(data: Data) {
        let baseUrl = "https://www.furaffinity.net/msg/submissions/"
        
        guard let string = String(data: data, encoding: .utf8),
              let doc = try? SwiftSoup.parse(string, baseUrl)
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
        do {
            let sidStr = try node.attr("id")
            guard sidStr.hasPrefix("sid-") else { return nil }
            let index = sidStr.index(sidStr.startIndex, offsetBy: 4)
            let sid = Int(String(sidStr[index...]))!
            self.sid = sid
            self.url = URL(string: "https://www.furaffinity.net/view/\(sid)/")!
            
            let thumbNodes = try node.select("figure b u a img")
            guard let thumbSrc = try thumbNodes.first()?.attr("src") else { return nil }
            self.thumbnailUrl = URL(string: "https:\(thumbSrc)")!
            
            let captionNodes = try node.select("figure figcaption label p a")
            self.title = try captionNodes[0].text()
            self.author = try captionNodes[1].attr("href")
                .substring(matching: "/user/(.+)/")!
            self.displayAuthor = try captionNodes[1].text()
        } catch {
            return nil
        }
    }
}
