//
//  FATargetTests.swift
//  FurAffinityTests
//
//  Created by Ceylo on 17/03/2023.
//

import Testing
import Foundation
@testable import Fur_Affinity

struct FATargetTests {
    @Test
    func notMatching() {
        let url = URL(string: "https://www.patreon.com/")!
        #expect(FATarget(with: url) == nil)
    }

    @Test
    func matchingUser() {
        let userUrl = URL(string: "https://www.furaffinity.net/user/xyz")!
        #expect(FATarget(with: userUrl) == .user(url: userUrl, previewData: nil))
    }

    @Test
    func matchingSubmission() {
        let submissionUrl = URL(string: "https://www.furaffinity.net/view/123/")!
        #expect(FATarget(with: submissionUrl) == .submission(url: submissionUrl, previewData: nil))
    }

    @Test
    func matchingNote() {
        let noteUrl = URL(string: "https://www.furaffinity.net/msg/pms/1/234/#message")!
        #expect(FATarget(with: noteUrl) == .note(url: noteUrl))
    }

    @Test
    func matchingJournal() {
        let journalUrl = URL(string: "https://www.furaffinity.net/journal/10516170/")!
        #expect(FATarget(with: journalUrl) == .journal(url: journalUrl))
    }

    @Test
    func matchingGallery() {
        let galleryUrl = URL(string: "https://www.furaffinity.net/gallery/username/")!
        #expect(FATarget(with: galleryUrl) == .gallery(url: galleryUrl))
    }

    @Test
    func matchingScraps() {
        let scrapsUrl = URL(string: "https://www.furaffinity.net/scraps/username/")!
        #expect(FATarget(with: scrapsUrl) == .gallery(url: scrapsUrl))
    }

    @Test
    func matchingFavorites() {
        let favoritesUrl = URL(string: "https://www.furaffinity.net/favorites/username/")!
        #expect(FATarget(with: favoritesUrl) == .favorites(url: favoritesUrl))
    }

    @Test
    func matchingJournalsPage() {
        let journalsUrl = URL(string: "https://www.furaffinity.net/journals/username/")!
        #expect(FATarget(with: journalsUrl) == .journals(url: journalsUrl))
    }

    @Test
    func matchingWatchlistByDirection() {
        let watchlistUrl = URL(string: "https://www.furaffinity.net/watchlist/by/username/")!
        #expect(FATarget(with: watchlistUrl) == .watchlist(url: watchlistUrl))
    }

    @Test
    func matchingWatchlistToDirection() {
        let watchlistUrl = URL(string: "https://www.furaffinity.net/watchlist/to/username/")!
        #expect(FATarget(with: watchlistUrl) == .watchlist(url: watchlistUrl))
    }

    @Test
    func httpSchemeIsNormalized() {
        let httpUrl = URL(string: "http://www.furaffinity.net/view/123/")!
        let httpsUrl = URL(string: "https://www.furaffinity.net/view/123/")!
        #expect(FATarget(with: httpUrl) == .submission(url: httpsUrl, previewData: nil))
    }
}
