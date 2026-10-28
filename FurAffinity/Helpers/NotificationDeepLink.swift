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
/// Routing comes from the FA URL alone: `FATarget(with:)` is its single interpreter,
/// down to which tab to open. This keeps notifications posted by older app versions routable and
/// avoids any need for a payload version field. A submission's preview rides along
/// only to show it sooner.
enum NotificationDeepLink {
    static let urlKey = "fa.deeplink.url"
    /// A submission's `FASubmissionPreview` as a JSON string, so the tapped submission
    /// shows its preview before the page loads. A string survives Android's `userInfo`.
    static let submissionPreviewKey = "fa.deeplink.submissionPreview"

    static func encode(_ preview: FASubmissionPreview) -> String? {
        (try? JSONEncoder().encode(preview)).map { String(decoding: $0, as: UTF8.self) }
    }

    /// Decodes the submission preview from a notification's `userInfo`, or nil when
    /// absent (non-submission, or posted by an older version) or undecodable.
    static func submissionPreview(fromUserInfo userInfo: [AnyHashable: Any]) -> FASubmissionPreview? {
        guard let json = userInfo[submissionPreviewKey] as? String else {
            return nil
        }
        do {
            return try JSONDecoder().decode(FASubmissionPreview.self, from: Data(json.utf8))
        } catch {
            logger.error("Failed to decode submission preview: \(error)")
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
    /// `submissionPreview` is attached when the URL is a submission.
    func setPendingDeepLink(fromURLString urlString: String?, submissionPreview: FASubmissionPreview? = nil) {
        guard let urlString else {
            return
        }
        guard var target = URL(string: urlString).flatMap(FATarget.init(with:)) else {
            logger.error("Deep link is not an in-app target: \(urlString)")
            return
        }
        if case let .submission(url, nil) = target, let submissionPreview {
            target = .submission(url: url, previewData: submissionPreview)
        }
        pendingDeepLink = target
    }
}
