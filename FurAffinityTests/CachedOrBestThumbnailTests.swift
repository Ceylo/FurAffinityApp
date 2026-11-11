//
//  CachedOrBestThumbnailTests.swift
//  FurAffinityTests
//

import FAKit
import Foundation
import Testing
#if FA_SKIP_MODULE
@testable import FurAffinityUI
#else
@testable import Fur_Affinity
#endif

struct CachedOrBestThumbnailTests {
    private func thumbnail() -> DynamicThumbnail {
        DynamicThumbnail(thumbnailUrl: URL(string: "https://t.furaffinity.net/\(UUID().uuidString)@200-1.jpg")!)
    }

    private func url(_ thumbnail: DynamicThumbnail, size: Int) -> URL {
        thumbnail.allThumbnailUrls.first { $0.absoluteString.contains("@\(size)-") }!
    }

    @Test
    func prefersACachedSmallerSizeOverAnUncachedBest() throws {
        let thumbnail = thumbnail()
        try seedImageCache(Data("jpeg".utf8), for: url(thumbnail, size: 400))
        #expect(thumbnail.cachedOrBestThumbnailUrl(for: CGSize(width: 390, height: 520)) == url(thumbnail, size: 400))
    }

    @Test
    func keepsTheBestWhenItIsCached() throws {
        let thumbnail = thumbnail()
        try seedImageCache(Data("jpeg".utf8), for: url(thumbnail, size: 400))
        try seedImageCache(Data("jpeg".utf8), for: url(thumbnail, size: 600))
        #expect(thumbnail.cachedOrBestThumbnailUrl(for: CGSize(width: 390, height: 520)) == url(thumbnail, size: 600))
    }

    @Test
    func fallsBackToTheBestWhenNothingIsCached() {
        let thumbnail = thumbnail()
        #expect(thumbnail.cachedOrBestThumbnailUrl(for: CGSize(width: 390, height: 520)) == url(thumbnail, size: 600))
    }
}
