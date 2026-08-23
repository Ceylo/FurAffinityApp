//
//  UserProfileControlTests.swift
//  FurAffinityTests
//

import FAKit
import Foundation
import Testing

@testable import Fur_Affinity

struct UserProfileControlTests {
    private let user = "someone"

    @Test
    func gallery() {
        #expect(UserProfileControl.gallery.target(for: user)
                == .gallery(url: FAURLs.galleryUrl(for: user)))
    }

    @Test
    func favorites() {
        #expect(UserProfileControl.favorites.target(for: user)
                == .favorites(url: FAURLs.favoritesUrl(for: user)))
    }

    @Test
    func journals() {
        #expect(UserProfileControl.journals.target(for: user)
                == .journals(url: FAURLs.journalsUrl(for: user)))
    }

    @Test
    func watching() {
        #expect(UserProfileControl.watching.target(for: user)
                == .watchlist(url: FAURLs.watchlistUrl(for: user, page: 1, direction: .watching)))
    }

    @Test
    func watchedBy() {
        #expect(UserProfileControl.watchedBy.target(for: user)
                == .watchlist(url: FAURLs.watchlistUrl(for: user, page: 1, direction: .watchedBy)))
    }

    @Test
    func everyControlURLIsRoutable() {
        // The URLs FAURLs mints must match FATarget's patterns, or a tap would
        // fall through to an external open.
        let urls = [
            FAURLs.galleryUrl(for: user),
            FAURLs.favoritesUrl(for: user),
            FAURLs.journalsUrl(for: user),
            FAURLs.watchlistUrl(for: user, page: 1, direction: .watching),
            FAURLs.watchlistUrl(for: user, page: 1, direction: .watchedBy),
        ]
        for url in urls {
            #expect(FATarget(with: url) != nil, "\(url) is not routable")
        }
    }
}
