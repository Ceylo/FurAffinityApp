//
//  InAppNavigation.swift
//  FurAffinity
//
//  Created by Ceylo on 17/03/2023.
//

import Foundation

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
