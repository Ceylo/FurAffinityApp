//
//  FAUserGalleryLikePage.swift
//  
//
//  Created by Ceylo on 31/08/2023.
//

import Foundation
@preconcurrency import SwiftSoup

public struct FAFolderGroup: Sendable, Hashable, Identifiable {
    public let title: String?
    public let folders: [FAFolder]
    public let id: UUID
    
    public init(title: String?, folders: [FAFolder], id: UUID = UUID()) {
        self.title = title
        self.folders = folders
        self.id = id
    }
}

public struct FAFolder: Sendable, Hashable, Identifiable {
    public let title: String
    public let url: URL
    public let isActive: Bool
    public let id: UUID
    
    public init(title: String, url: URL, isActive: Bool, id: UUID = UUID()) {
        self.title = title
        self.url = url
        self.isActive = isActive
        self.id = id
    }
}

public struct FAUserGalleryLikePage: Sendable {
    public let previews: [FASubmissionsPage.Submission?]
    public let displayAuthor: String
    public let nextPageUrl: URL?
    public let folderGroups: [FAFolderGroup]
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
            async let previews = items.map { FASubmissionsPage.Submission($0) }
            
            let userNode = try siteContentNode.select(
                "userpage-nav-header userpage-nav-user-details username div.c-usernameBlock a.c-usernameBlock__displayName"
            )
            self.displayAuthor = try userNode.text()
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
            
            let folderItemsQuery = "div#page-galleryscraps div#columnpage div div.folder-list div.user-folders"
            let userItems = try siteContentNode.select(folderItemsQuery)
            self.folderGroups = try Self.parseFolderGroups(from: userItems, currentUrl: url)
        } catch {
            logger.error("\(#file, privacy: .public) - \(error, privacy: .public)")
            return nil
        }
    }
    
    static func parseFolderGroups(from node: SwiftSoup.Elements, currentUrl: URL) throws -> [FAFolderGroup] {
        guard node.count == 1 else {
            if node.count == 0 {
                return []
            } else {
                throw FAPagesError.unexpectedStructure
            }
        }
        
        func parseFolder(in liNode: SwiftSoup.Element) throws -> FAFolder {
            var title = try liNode.text()
            if title.starts(with: "❯❯ ") {
                title = String(title.dropFirst(3))
            }
            let isActive = liNode.hasClass("active")
            let url: URL
            if let linkNode = try? liNode.select("a").first() {
                let urlStr = try linkNode.attr("href")
                url = try URL(string: FAURLs.homeUrl.absoluteString + urlStr).unwrap()
            } else {
                url = currentUrl
            }
            return .init(title: title, url: url, isActive: isActive)
        }
        
        var folderGroups = [FAFolderGroup]()
        var unfinishedFolderGroupTitle: String?
        
        for child in node[0].children() {
            if child.tagName() == "div" && child.hasClass("container-item-top") {
                unfinishedFolderGroupTitle = try child.text()
            } else if (child.tagName() == "div" && child.hasClass("default-folders")) || child.tagName() == "ul" {
                // HTML structure is modified on mobile and first item is missing
                if unfinishedFolderGroupTitle == nil && folderGroups.isEmpty {
                    unfinishedFolderGroupTitle = "Gallery Folders"
                }
                let folders = try child.select("li").map(parseFolder)
                folderGroups.append(.init(
                    title: unfinishedFolderGroupTitle.take(),
                    folders: folders
                ))
            } else {
                let html = (try? child.html()) ?? ""
                logger.error("Unhandled tag \(child.tagName(), privacy: .public) in \(html, privacy: .public)")
                throw FAPagesError.unexpectedStructure
            }
        }
        
        return folderGroups
    }
}
