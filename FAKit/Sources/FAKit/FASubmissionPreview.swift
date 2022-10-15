//
//  FASubmissionPreview.swift
//  
//
//  Created by Ceylo on 21/11/2021.
//

import Foundation
import FAPages

public struct FASubmissionPreview: Equatable, Identifiable {
    public let sid: Int
    public let url: URL
    public let thumbnailUrl: URL
    public let thumbnailWidthOnHeightRatio: Float
    public let title: String
    public let author: String
    public let displayAuthor: String
    public var id: Int { sid }
    
    public init(sid: Int, url: URL, thumbnailUrl: URL, thumbnailWidthOnHeightRatio: Float, title: String, author: String, displayAuthor: String) {
        self.sid = sid
        self.url = url
        self.thumbnailUrl = thumbnailUrl
        self.thumbnailWidthOnHeightRatio = thumbnailWidthOnHeightRatio
        self.title = title
        self.author = author
        self.displayAuthor = displayAuthor
    }
}

public extension FASubmissionPreview {
    init(_ submission: FASubmissionsPage.Submission) {
        self.init(sid: submission.sid,
                  url: submission.url,
                  thumbnailUrl: submission.thumbnailUrl,
                  thumbnailWidthOnHeightRatio: submission.thumbnailWidthOnHeightRatio,
                  title: submission.title,
                  author: submission.author,
                  displayAuthor: submission.displayAuthor)
    }
}

public extension FASubmissionPreview {
    enum ThumbnailSize: Int, CaseIterable {
        case s50 = 50
        case s75 = 75
        case s100 = 100
        case s120 = 120
        case s200 = 200
        case s300 = 300
        case s320 = 320
        case s400 = 400
        case s600 = 600
        case s800 = 800
        case s1600 = 1600
    }
    
    func thumbnailUrl(at size: ThumbnailSize) -> URL {
        URL(string: thumbnailUrl.absoluteString
                .replacingFirst(matching: "(.+)(@\\d+-)(.+)",
                                with: "$1\\@\(size.rawValue)-$3"))!
    }
    
    func bestThumbnailUrl(for size: UInt) -> URL {
        let match = ThumbnailSize.allCases.first { $0.rawValue > size }
        let size = match ?? ThumbnailSize.allCases.last!
        return thumbnailUrl(at: size)
    }
}
