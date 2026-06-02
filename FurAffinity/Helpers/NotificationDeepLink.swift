//
//  NotificationDeepLink.swift
//  FurAffinity
//
//  Created by Ceylo on 02/06/2026.
//

import Foundation
import Observation
import UserNotifications

/// Contract for the deep-link payload carried by local notifications.
///
/// Only the FA URL is stored: `FATarget(with:)` is the single interpreter of
/// that URL, so routing (including which tab to open) is derived from the URL
/// itself. This keeps notifications posted by older app versions routable and
/// avoids any need for a payload version field.
enum NotificationDeepLink {
    static let urlKey = "fa.deeplink.url"
}

/// Receives notification taps and exposes the resulting deep-link target.
///
/// There is no SwiftUI-native API for notification responses, but we don't need
/// a `UIApplicationDelegateAdaptor`: this object is set as
/// `UNUserNotificationCenter`'s delegate at launch and published into the
/// environment. `pendingDeepLink` is set on tap and drained by `LoggedInView`.
@Observable @MainActor
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationCoordinator()

    /// The target to navigate to from the most recent notification tap, or nil
    /// once consumed. Buffered here so a tap that cold-launches the app is
    /// honored once `LoggedInView` mounts.
    var pendingDeepLink: FATarget?

    // Async delegate variant (iOS 15+); avoids completion handlers.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        // Extract the Sendable String off-actor, then hop to the main actor.
        let urlString = response.notification.request.content
            .userInfo[NotificationDeepLink.urlKey] as? String
        await setPendingDeepLink(fromURLString: urlString)
    }

    /// Parses an FA URL string into a navigable target. No-op (leaves
    /// `pendingDeepLink` unchanged at nil) for missing/unmappable URLs.
    func setPendingDeepLink(fromURLString urlString: String?) {
        guard let urlString,
              let url = URL(string: urlString),
              let target = FATarget(with: url) else {
            return
        }
        pendingDeepLink = target
    }
}
