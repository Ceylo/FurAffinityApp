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

    // MARK: - carriesCloudflareClearance

    @Test
    func clearancePresentInAHeader() {
        #expect("a=1; cf_clearance=abc; b=2".carriesCloudflareClearance)
        #expect("cf_clearance=abc".carriesCloudflareClearance)
        #expect("a=1; cf_clearance=abc".carriesCloudflareClearance)
    }

    @Test
    func clearanceAbsentFromAHeader() {
        #expect(!"a=1; b=2".carriesCloudflareClearance)
    }

    @Test
    func emptyHeaderCarriesNothing() {
        #expect(!"".carriesCloudflareClearance)
    }

    /// The reason this matches on the cookie *name* rather than substring: a
    /// `contains("cf_clearance=")` would accept every one of these.
    @Test
    func aNamePrefixIsNotAClearance() {
        #expect(!"xcf_clearance=abc".carriesCloudflareClearance)
        #expect(!"a=1; xcf_clearance=abc".carriesCloudflareClearance)
        #expect(!"not_cf_clearance=abc".carriesCloudflareClearance)
    }
}
