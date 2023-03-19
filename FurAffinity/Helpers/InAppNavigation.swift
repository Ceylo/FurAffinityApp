//
//  InAppNavigation.swift
//  FurAffinity
//
//  Created by Ceylo on 17/03/2023.
//

import SwiftUI

let appNavigationScheme = "furaffinity-app-navigation"

extension AttributedString {
    func convertingLinksForInAppNavigation() -> AttributedString {
        self.transformingAttributes(\.link) { link in
            if let url = link.value, FAURL(with: url) != nil {
                link.value = url.replacingScheme(with: appNavigationScheme)
            }
        }
    }
}

@ViewBuilder
func view(for url: FAURL) -> some View {
    switch url {
    case let .submission(url):
        SubmissionView(url: url)
    case let .note(url):
        NoteView(url: url)
    case let .user(url):
        UserView(url: url)
    }
}
