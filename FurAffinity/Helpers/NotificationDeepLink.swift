//
//  NotificationDeepLink.swift
//  FurAffinity
//
//  Created by Ceylo on 02/06/2026.
//

import Foundation

/// Contract for the deep-link payload carried by local notifications.
///
/// Only the FA URL is stored: `FATarget(with:)` is the single interpreter of
/// that URL, so routing (including which tab to open) is derived from the URL
/// itself. This keeps notifications posted by older app versions routable and
/// avoids any need for a payload version field.
enum NotificationDeepLink {
    static let urlKey = "fa.deeplink.url"
}
