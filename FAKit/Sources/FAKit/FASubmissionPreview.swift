//
//  FASubmissionPreview.swift
//  
//
//  Created by Ceylo on 21/11/2021.
//

import Foundation
import FAPages

public struct FASubmissionPreview: Hashable, Identifiable, Sendable {
    public let sid: Int
    public let url: URL
    public let thumbnailUrl: URL
    public let thumbnailWidthOnHeightRatio: Float
    public let title: String
    public let author: String
    public let displayAuthor: String
    public var id: Int { sid }
    public let dynamicThumbnail: DynamicThumbnail
    
    public init(sid: Int, url: URL, thumbnailUrl: URL, thumbnailWidthOnHeightRatio: Float, title: String, author: String, displayAuthor: String) {
        self.sid = sid
        self.url = url
        self.thumbnailUrl = thumbnailUrl
        self.thumbnailWidthOnHeightRatio = thumbnailWidthOnHeightRatio
        self.title = title
        self.author = author
        self.displayAuthor = displayAuthor
        self.dynamicThumbnail = .init(thumbnailUrl: thumbnailUrl)
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

extension FASubmissionPreview: Comparable {
    public static func < (lhs: FASubmissionPreview, rhs: FASubmissionPreview) -> Bool {
        lhs.sid < rhs.sid
    }
}
