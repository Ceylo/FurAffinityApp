//
//  File.swift
//  
//
//  Created by Ceylo on 17/06/2024.
//

import SwiftUI

public struct DynamicThumbnail: Hashable, Sendable {
    private let thumbnailUrl: URL
    // Empirically determined from thumbnail sizes in
    // https://www.furaffinity.net/msg/submissions/
    // Trying to use larger sizes will redirect to fit this size.
    // FA+ users may have a higher limit.
    private static let maximumThumbnailSize = CGSize(width: 600, height: 600)
    
    public init(thumbnailUrl: URL) {
        self.thumbnailUrl = thumbnailUrl
    }
    
    private enum ThumbnailSize: Int, CaseIterable {
        case s200 = 200
        case s300 = 300
        case s320 = 320
        case s400 = 400
        case s600 = 600
    }

    private func thumbnailUrl(at size: ThumbnailSize) -> URL {
        let regex = #/(.+@)(\d+)(-.+)/#
        let newUrl = thumbnailUrl.absoluteString
            .replacing(regex) { $0.1 + "\(size.rawValue)" + $0.3 }
        return URL(string: newUrl)!
    }

    private func bestThumbnailUrl(for size: UInt) -> URL {
        let match = ThumbnailSize.allCases.first { $0.rawValue >= size }
        let discreteSize = match ?? ThumbnailSize.allCases.last!
        return thumbnailUrl(at: discreteSize)
    }
    
    public func bestThumbnailUrl(for size: CGSize) -> URL {
        let size = size.fitting(in: Self.maximumThumbnailSize)
        return bestThumbnailUrl(for: UInt(size.maxDimension))
    }
    
    public func bestThumbnailUrl(for geometry: GeometryProxy) -> URL {
        bestThumbnailUrl(for: geometry.size)
    }
}
