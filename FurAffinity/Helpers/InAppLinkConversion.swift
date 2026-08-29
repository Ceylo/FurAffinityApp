//
//  InAppLinkConversion.swift
//  FurAffinity
//
//  Home of the app's URL scheme, kept apart from `InAppNavigation.swift` so the Android
//  target can compile it: that file's other half is `view(for:)`, which names eight
//  `Remote*View`s Android doesn't have yet. Foundation and FAKit only — no SwiftUI — is
//  what makes this side portable.
//

import Foundation
import FAKit

/// External entry point only — saved URLs in Reminders, Shortcuts and the like,
/// delivered to iOS through `.onOpenURL`. In-app links on either platform never use it:
/// they route in-process through `NavigationStream`. Android registers no scheme at all
/// (`Android/app/src/main/AndroidManifest.xml` declares only `MAIN`/`LAUNCHER`).
///
/// - Important: must stay in sync with `CFBundleURLSchemes` in `FurAffinity/iOS/Info.plist`.
let appNavigationScheme = "furaffinity-app-navigation"
