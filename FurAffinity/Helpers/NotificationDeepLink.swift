//
//  NotificationDeepLink.swift
//  FurAffinity
//
//  Created by Ceylo on 02/06/2026.
//

import FAKit
import Foundation
import SwiftUI

/// Contract for the deep-link payload carried by local notifications.
///
/// Only the FA URL is stored: `FATarget(with:)` is the single interpreter of
/// that URL, so routing (including which tab to open) is derived from the URL
/// itself. This keeps notifications posted by older app versions routable and
/// avoids any need for a payload version field.
enum NotificationDeepLink {
    static let urlKey = "fa.deeplink.url"
    /// A submission's `FASubmissionPreview` as a JSON string, so the tapped submission
    /// shows its preview before the page loads. A string survives Android's `userInfo`.
    static let submissionPreviewKey = "fa.deeplink.submissionPreview"

    static func encode(_ preview: FASubmissionPreview) -> String? {
        do {
            return String(decoding: try JSONEncoder().encode(preview), as: UTF8.self)
        } catch {
            logger.error("Failed to encode submission preview: \(error)")
            return nil
        }
    }
}

/// Exposes the deep-link target of the latest notification tap.
///
/// Each platform's `NotificationCenterDelegate` feeds it; it is published into the
/// environment, and `pendingDeepLink` is drained by `LoggedInView` (`AndroidRootView`
/// on Android).
@Observable @MainActor
final class NotificationCoordinator {
    static let shared = NotificationCoordinator()

    /// The target to navigate to from the most recent notification tap, or nil
    /// once consumed. Buffered here so a tap that cold-launches the app is
    /// honored once `LoggedInView` mounts.
    var pendingDeepLink: FATarget?

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
        guard let urlString else {
            return
        }
        guard let target = URL(string: urlString).flatMap(FATarget.init(with:)) else {
            logger.error("Deep link is not an in-app target: \(urlString)")
            return
        }
        pendingDeepLink = target
    }
}
