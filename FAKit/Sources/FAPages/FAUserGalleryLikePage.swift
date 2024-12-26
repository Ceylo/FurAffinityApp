//
//  FAUserGalleryLikePage.swift
//  
//
//  Created by Ceylo on 31/08/2023.
//

import Foundation
@preconcurrency import SwiftSoup

public enum FAFolderItem: Sendable, Equatable {
    case section(title: String)
    case folder(title: String, url: URL)
}

public struct FAUserGalleryLikePage: Sendable {
    public let previews: [FASubmissionsPage.Submission?]
    public let displayAuthor: String
    public let nextPageUrl: URL?
    public let folderItems: [FAFolderItem]
}

extension FAUserGalleryLikePage {
    public init?(data: Data, url: URL) async {
        let state = signposter.beginInterval("User Gallery Parsing")
        defer { signposter.endInterval("User Gallery Parsing", state) }
        
        do {
            let string = String(decoding: data, as: UTF8.self)
            let doc = try SwiftSoup.parse(string)
            
            let siteContentNode = try doc.select(
                "html body div#main-window div#site-content"
            )
            let itemsQuery = "section.gallery-section div.section-body section figure"
            let items = try siteContentNode.select(itemsQuery)
            async let previews = items.parallelMap { FASubmissionsPage.Submission($0) }
            
            let userNode = try siteContentNode.select(
                "userpage-nav-header userpage-nav-user-details h1 username"
            )
            self.displayAuthor = try String(userNode.text().dropFirst())
            self.previews = await previews
            
            let navigationFormsQuery = "section.gallery-section div.section-body div.gallery-navigation div form"
            let nextButtonForm = try? siteContentNode
                .select(navigationFormsQuery)
                .first(where: {
                    try $0.text() == "Next"
                })
            if let nextButtonForm {
                let relativeUrl = try nextButtonForm.attr("action")
                self.nextPageUrl = try URL(unsafeString: FAURLs.homeUrl.absoluteString + relativeUrl)
            } else {
                self.nextPageUrl = nil
            }
            
            let folderItemsQuery = "div#page-galleryscraps div#columnpage div.sidebar div.folder-list div.user-folders"
            let userItems = try siteContentNode.select(folderItemsQuery)
            self.folderItems = try Self.parseFolderItems(from: userItems, currentUrl: url)
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            return nil
        }
    }
    
    static func parseFolderItems(from node: SwiftSoup.Elements, currentUrl: URL) throws -> [FAFolderItem] {
        enum Error: Swift.Error {
            case unexpectedStructure
        }
        
        guard node.count == 1 else {
            if node.count == 0 {
                return []
            } else {
                throw Error.unexpectedStructure
            }
        }
        
        func parseFolder(in liNode: SwiftSoup.Element) throws -> FAFolderItem {
            let title = try liNode.text()
            let url: URL
            if let linkNode = try? liNode.select("a").first() {
                let urlStr = try linkNode.attr("href")
                url = try URL(string: FAURLs.homeUrl.absoluteString + urlStr).unwrap()
            } else {
                url = currentUrl
            }
            return .folder(title: title, url: url)
        }
        
        var folderItems = [FAFolderItem]()
        for child in node[0].children() {
            if child.tagName() == "div" && child.hasClass("container-item-top") {
                let title = try child.text()
                folderItems.append(.section(title: title))
            } else if child.tagName() == "div" && child.hasClass("default-folders") {
                folderItems.append(contentsOf: try child.select("li").map(parseFolder))
            } else if child.tagName() == "ul" {
                folderItems.append(contentsOf: try child.select("li").map(parseFolder))
            } else {
                let html = (try? child.html()) ?? ""
                logger.error("Unhandled tag \(child.tagName(), privacy: .public) in \(html, privacy: .public)")
                throw Error.unexpectedStructure
            }
        }
        return folderItems
    }
}
