//
//  UserProfileControl.swift
//  FurAffinity
//
//  Created by Ceylo on 04/09/2024.
//

import Foundation
import FAKit

enum UserProfileControl: Int, CaseIterable, Identifiable {
    var id: Int { rawValue }

    case gallery
    case favorites
    case journals
    case watching
    case watchedBy
}

extension UserProfileControl {
    var title: String {
        switch self {
        case .gallery: "Gallery"
        case .favorites: "Favorites"
        case .journals: "Journals"
        case .watching: "Watching"
        case .watchedBy: "Watched By"
        }
    }
    
    func target(for user: String) -> FATarget {
        switch self {
        case .gallery:
            .gallery(url: FAURLs.galleryUrl(for: user))
        case .favorites:
            .favorites(url: FAURLs.favoritesUrl(for: user))
        case .journals:
            .journals(url: FAURLs.journalsUrl(for: user))
        case .watching:
            .watchlist(url: FAURLs.watchlistUrl(for: user, page: 1, direction: .watching))
        case .watchedBy:
            .watchlist(url: FAURLs.watchlistUrl(for: user, page: 1, direction: .watchedBy))
        }
    }
}
