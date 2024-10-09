//
//  DynamicThumbnailTests.swift
//  FAKit
//
//  Created by Ceylo on 07/10/2024.
//

import Testing
import Foundation
@testable import FAKit

struct CGSizeTests {
    @Test("fitting", arguments: [
        (CGSize(100, 100), CGSize(100, 100), CGSize(100, 100)),
        (CGSize(100, 100), CGSize(200, 200), CGSize(100, 100)),
        (CGSize(100, 100), CGSize(50, 50), CGSize(50, 50)),
        (CGSize(100, 100), CGSize(80, 50), CGSize(50, 50)),
        (CGSize(80, 50), CGSize(80, 50), CGSize(80, 50)),
        (CGSize(80, 50), CGSize(50, 80), CGSize(50, 31.25)),
        (CGSize(50, 80), CGSize(50, 80), CGSize(50, 80)),
        (CGSize(50, 80), CGSize(80, 50), CGSize(31.25, 50)),
    ])
    func fitting(srcSize: CGSize, constraint: CGSize, expected: CGSize) async throws {
        #expect(srcSize.fitting(in: constraint) == expected)
    }
}

struct DynamicThumbnailTests {
    static let baseUrl = "https://t.fa/123@100-123.jpg"
    
    @Test("bestThumbnailUrl", arguments: [
        (baseUrl, (300, 600), "https://t.fa/123@600-123.jpg"),
        (baseUrl, (600, 300), "https://t.fa/123@600-123.jpg"),
        (baseUrl, (900, 300), "https://t.fa/123@600-123.jpg"),
        (baseUrl, (300, 900), "https://t.fa/123@600-123.jpg"),
        (baseUrl, (300, 300), "https://t.fa/123@300-123.jpg"),
        (baseUrl, (30, 30), "https://t.fa/123@200-123.jpg"),
    ])
    func bestThumbnailUrl(url: String, size: (CGFloat, CGFloat), expected: String) async throws {
        let url = try URL(string: url).unwrap()
        let expected = try URL(string: expected).unwrap()
        let thumbnail = DynamicThumbnail(thumbnailUrl: url)
        let size = CGSize(width: size.0, height: size.1)
        #expect(thumbnail.bestThumbnailUrl(for: size) == expected)
    }
}
