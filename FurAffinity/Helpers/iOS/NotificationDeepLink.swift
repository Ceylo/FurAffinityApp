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

    // Completion-handler delegate variant. We call `completionHandler()`
    // synchronously and immediately, and never touch `@MainActor` state inline:
    // the system finishes handling the response (and the foreground transition
    // on a tap) only once this method returns. The async variant returned only
    // after an `await` hop onto the (possibly busy) main actor, which delayed
    // the implicit completion and could keep the app from foregrounding. Here
    // the main-actor work is handed off to a detached `Task` instead.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        // Extract the Sendable String off-actor; do NOT block on a main-actor hop here.
        let urlString = Self.deepLinkURLString(fromUserInfo: response.notification.request.content.userInfo)
        if let urlString {
            Task { @MainActor in
                NotificationCoordinator.shared.setPendingDeepLink(fromURLString: urlString)
            }
        }
        // Signal completion right away so the system finishes foregrounding the app.
        completionHandler()
    }

    /// Pulls the deep-link URL string out of a notification's `userInfo`.
    /// Returns nil when the key is absent or not a string. Factored out so the
    /// extraction seam is unit-testable without constructing a
    /// `UNNotificationResponse`.
    nonisolated static func deepLinkURLString(fromUserInfo userInfo: [AnyHashable: Any]) -> String? {
        userInfo[NotificationDeepLink.urlKey] as? String
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
