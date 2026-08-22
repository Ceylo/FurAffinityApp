//
//  LinkActivationTests.swift
//  FurAffinityTests
//

import Foundation
import Testing

@testable import Fur_Affinity

struct LinkActivationTests {
    @Test
    func faURLNavigatesInApp() {
        let url = URL(string: "https://www.furaffinity.net/view/123/")!
        #expect(LinkActivation(for: url) == .navigate(.submission(url: url, previewData: nil)))
    }

    @Test
    func customSchemeStillResolves() {
        // External entry points (Reminders, Shortcuts) keep minting these.
        let url = URL(string: "\(appNavigationScheme)://www.furaffinity.net/view/123/")!
        let httpsUrl = URL(string: "https://www.furaffinity.net/view/123/")!
        #expect(LinkActivation(for: url) == .navigate(.submission(url: httpsUrl, previewData: nil)))
    }

    @Test
    func nonFAURLOpensExternally() {
        #expect(LinkActivation(for: URL(string: "https://ko-fi.com/x")!) == .openExternally)
    }

    @Test
    func unroutableFAURLOpensExternally() {
        #expect(LinkActivation(for: URL(string: "https://www.furaffinity.net/settings/")!) == .openExternally)
    }
}
