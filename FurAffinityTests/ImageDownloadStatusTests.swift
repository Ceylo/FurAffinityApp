//
//  ImageDownloadStatusTests.swift
//  FurAffinityTests
//

import Foundation
import Testing
import Kingfisher
@testable import Fur_Affinity

struct ImageDownloadStatusTests {
    private let downloader = ImageDownloader(name: "ImageDownloadStatusTests")
    private let url = URL(string: "https://d.furaffinity.net/art/typhin/stories/1783669566/1642368831.thumbnail.typhin_princess_tells_her_story.pdf.gif")!

    private func response(status: Int, contentType: String) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/2", headerFields: ["Content-Type": contentType])!
    }

    @Test @MainActor
    func notFoundPassesTheStatusCheck() {
        let delegate = DownloadDelegate.shared
        #expect(delegate.isValidStatusCode(200, for: downloader))
        #expect(delegate.isValidStatusCode(404, for: downloader))
        #expect(!delegate.isValidStatusCode(403, for: downloader))
        #expect(!delegate.isValidStatusCode(500, for: downloader))
    }

    @Test @MainActor
    func notFoundIsDownloadedOnlyWhenItIsAnImage() async {
        let delegate = DownloadDelegate.shared
        let placeholder = await delegate.imageDownloader(downloader, didReceive: response(status: 404, contentType: "image/gif"))
        let page = await delegate.imageDownloader(downloader, didReceive: response(status: 404, contentType: "text/html; charset=UTF-8"))
        let found = await delegate.imageDownloader(downloader, didReceive: response(status: 200, contentType: "text/html"))
        #expect(placeholder == .allow)
        #expect(page == .cancel)
        #expect(found == .allow)
    }
}
