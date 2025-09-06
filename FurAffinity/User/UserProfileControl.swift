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
    
    func destinationUrl(for user: String) -> URL {
        switch self {
        case .gallery:
            FAURLs.galleryUrl(for: user)
                .convertedForInAppNavigation
        case .favorites:
            FAURLs.favoritesUrl(for: user)
                .convertedForInAppNavigation
        case .journals:
            FAURLs.journalsUrl(for: user)
                .convertedForInAppNavigation
        case .watching:
            FAURLs.watchlistUrl(for: user, page: 1, direction: .watching)
                .convertedForInAppNavigation
        case .watchedBy:
            FAURLs.watchlistUrl(for: user, page: 1, direction: .watchedBy)
                .convertedForInAppNavigation
        }
    }
}
