//
//  InAppLinkConversion.swift
//  FurAffinity
//
//  The link-rewriting half of in-app navigation, kept apart from `InAppNavigation.swift`
//  so it can be symlinked into the Android target: that file's other half is
//  `view(for:)`, which names eight `Remote*View`s Android doesn't have yet. Foundation
//  and FAKit only — no SwiftUI — is what makes this side portable.
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
