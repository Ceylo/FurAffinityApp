//
//  File.swift
//  
//
//  Created by Ceylo on 17/06/2024.
//

import SwiftUI

public struct DynamicThumbnail: Hashable {
    private let thumbnailUrl: URL
    
    public init(thumbnailUrl: URL) {
        self.thumbnailUrl = thumbnailUrl
    }
    
    private enum ThumbnailSize: Int, CaseIterable {
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

    private func thumbnailUrl(at size: ThumbnailSize) -> URL {
        let regex = #/(.+@)(\d+)(-.+)/#
        let newUrl = thumbnailUrl.absoluteString
            .replacing(regex) { $0.1 + "\(size.rawValue)" + $0.3 }
        return URL(string: newUrl)!
    }

    private func bestThumbnailUrl(for size: UInt) -> URL {
        let match = ThumbnailSize.allCases.first { $0.rawValue > size }
        let discreteSize = match ?? ThumbnailSize.allCases.last!
        return thumbnailUrl(at: discreteSize)
    }
    
    public func bestThumbnailUrl(for geometry: GeometryProxy) -> URL {
        bestThumbnailUrl(for: UInt(geometry.size.maxDimension))
    }
}
