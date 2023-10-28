//
//  InAppNavigation.swift
//  FurAffinity
//
//  Created by Ceylo on 17/03/2023.
//

import SwiftUI
import FAKit

let appNavigationScheme = "furaffinity-app-navigation"

extension URL {
    var convertedForInAppNavigation: URL {
        guard FAURL(with: self) != nil else {
            return self
        }
        
        return self.replacingScheme(with: appNavigationScheme) ?? self
    }
}

extension AttributedString {
    func convertingLinksForInAppNavigation() -> AttributedString {
        self.transformingAttributes(\.link) { link in
            if let url = link.value {
                link.value = url.convertedForInAppNavigation
            }
        }
    }
}

func inAppUserUrl(for username: String) -> URL? {
    FAURLs.userpageUrl(for: username)?.convertedForInAppNavigation
}

@ViewBuilder
func view(for url: FAURL) -> some View {
    switch url {
    case let .submission(url):
        RemoteSubmissionView(url: url)
    case let .note(url):
        NoteView(url: url)
    case let .journal(url):
        RemoteJournalView(url: url)
    case let .user(url):
        RemoteUserView(url: url)
    case let .gallery(url):
        RemoteUserGalleryLikeView(galleryDisplayType: "gallery", url: url)
    case let .scraps(url):
        RemoteUserGalleryLikeView(galleryDisplayType: "scraps", url: url)
    case let .favorites(url):
        RemoteUserGalleryLikeView(galleryDisplayType: "favorites", url: url)
    }
}
