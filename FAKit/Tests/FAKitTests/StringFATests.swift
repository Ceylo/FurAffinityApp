//
//  StringFATests.swift
//  FAKit
//
//  Created by Ceylo on 30/05/2026.
//

import Testing
@testable import FAKit

struct StringFATests {
    @Test
    func relativeHrefIsExpanded() {
        let html = #"<a href="/view/123/">link</a>"#
        let result = html.selfContainedFAHtmlComment
        #expect(result.contains(#"href="https://www.furaffinity.net/view/123/""#))
    }

    @Test
    func relativeImgSrcIsExpanded() {
        let html = #"<img src="/themes/foo.png">"#
        let result = html.selfContainedFAHtmlComment
        #expect(result.contains(#"src="https://www.furaffinity.net/themes/foo.png""#))
    }

    @Test
    func protocolRelativeSrcIsExpanded() {
        let html = #"<img src="//t.furaffinity.net/img.jpg">"#
        let result = html.selfContainedFAHtmlComment
        #expect(result.contains(#"src="https://t.furaffinity.net/img.jpg""#))
    }

    @Test
    func emptyStringProducesHtmlSkeleton() {
        let result = "".selfContainedFAHtmlSubmission
        #expect(result.contains("<!DOCTYPE html"))
        #expect(result.contains("<body"))
        #expect(result.contains("</body>"))
    }
}
