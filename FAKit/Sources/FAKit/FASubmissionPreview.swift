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
    public let rating: Rating

    public init(sid: Int, url: URL, thumbnailUrl: URL, thumbnailWidthOnHeightRatio: Float, title: String, author: String, displayAuthor: String, rating: Rating) {
        self.sid = sid
        self.url = url
        self.thumbnailUrl = thumbnailUrl
        self.thumbnailWidthOnHeightRatio = thumbnailWidthOnHeightRatio
        self.title = title
        self.author = author
        self.displayAuthor = displayAuthor
        self.dynamicThumbnail = .init(thumbnailUrl: thumbnailUrl)
        self.rating = rating
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
                  displayAuthor: submission.displayAuthor,
                  rating: submission.rating)
    }
}

extension FASubmissionPreview: Comparable {
    public static func < (lhs: FASubmissionPreview, rhs: FASubmissionPreview) -> Bool {
        lhs.sid < rhs.sid
    }
}

extension FASubmissionPreview: Codable {
    /// `dynamicThumbnail` is derived from `thumbnailUrl`, so it is rebuilt rather than encoded.
    private enum CodingKeys: String, CodingKey {
        case sid, url, thumbnailUrl, thumbnailWidthOnHeightRatio, title, author, displayAuthor, rating
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(sid: try container.decode(Int.self, forKey: .sid),
                  url: try container.decode(URL.self, forKey: .url),
                  thumbnailUrl: try container.decode(URL.self, forKey: .thumbnailUrl),
                  thumbnailWidthOnHeightRatio: try container.decode(Float.self, forKey: .thumbnailWidthOnHeightRatio),
                  title: try container.decode(String.self, forKey: .title),
                  author: try container.decode(String.self, forKey: .author),
                  displayAuthor: try container.decode(String.self, forKey: .displayAuthor),
                  rating: try container.decode(Rating.self, forKey: .rating))
    }
}
