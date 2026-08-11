//
//  InAppLinkConversion.swift
//  FurAffinityUI (Android)
//
//  The link-rewriting half of the iOS `InAppNavigation.swift`. That file can't be
//  symlinked: its other half is `view(for:)`, which names eight `Remote*View`s that
//  don't exist on Android yet (see AndroidNavigationDestination.swift). Splitting the
//  iOS file in two would mean an .xcodeproj edit, so these ~20 lines are knowingly
//  duplicated instead — keep them in sync with InAppNavigation.swift.
//

import Foundation
import FAKit

let appNavigationScheme = "furaffinity-app-navigation"

extension URL {
    var convertedForInAppNavigation: URL {
        guard FATarget(with: self) != nil else {
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
