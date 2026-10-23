//
//  BackgroundRefreshManager+Android.swift
//  FurAffinityUI (Android)
//
//  Android's hooks for the shared background refresh: a periodic WorkManager job
//  (FABackgroundRefreshWorker.kt) runs it on a session built from the cookie jar
//  alone, and a notification without a thumbnail shows the author's avatar, where
//  iOS draws it through a communication notification.
//
//  Unguarded on purpose — an Android substitution file must be, see
//  Android/docs/shared-sources.md § Rules for shared sources. The JNI inside is `canImport(Android)`-guarded and no-ops on Darwin.
//

import Foundation
import FAKit
import Kingfisher
#if os(Android)
import SwiftUI
#else
import UserNotifications
#endif
#if canImport(Android)
import SkipBridge
#endif

extension BackgroundRefreshManager {
    /// Every 30 minutes, the earliest iOS asks for.
    static func schedule() {
        #if canImport(Android)
        let minutes: Int64 = 30
        do {
            let bridge = try AnyDynamicObject(className: "fur.affinity.ui.FANotificationBridge")
            let ok: Bool? = try bridge.scheduleBackgroundRefresh(minutes)
            if ok == true {
                logger.info("Scheduled background refresh (every \(minutes) min)")
            } else {
                logger.error("Failed scheduling background refresh")
            }
        } catch {
            logger.error("Could not reach FANotificationBridge: \(error)")
        }
        #endif
    }

    static func makeBackgroundSession() async throws -> OnlineFASession? {
        try await FAWebSession.makeBackgroundSession(source: .submissionsFeed(from: nil))
    }

    /// Attaches the author's avatar, which becomes the large icon, unless a submission
    /// thumbnail will take that place.
    static func enrich(_ content: UNMutableNotificationContent, for record: PendingNotificationRecord) async -> UNNotificationContent {
        guard record.thumbnailURLString == nil, let url = FAURLs.avatarUrl(for: record.author) else {
            return content
        }
        do {
            let file = try await KingfisherManager.shared.retrieveFAImageFile(with: url)
            content.attachments = [try UNNotificationAttachment(identifier: "avatar", url: file, options: nil)]
        } catch {
            logger.error("Failed to attach the avatar of \(record.author) at \(url): \(error)")
        }
        return content
    }

    /// A general submission's clear image also goes in hidden, which makes it the expanded
    /// picture. A mature submission's clear image, which iOS shows only on a long-press,
    /// waits behind a Show button: Android expands the top notification on its own.
    static func attaching(_ attachments: [UNNotificationAttachment], to content: UNNotificationContent) -> UNNotificationContent {
        guard let mutable = content as? UNMutableNotificationContent, let primary = attachments.first else {
            return content
        }
        let expanded: UNNotificationAttachment?
        if attachments.count == 1 {
            expanded = try? UNNotificationAttachment(identifier: "expanded", url: primary.url, options: [UNNotificationAttachmentOptionsThumbnailHiddenKey: true])
        } else {
            expanded = try? UNNotificationAttachment(identifier: attachments[1].identifier, url: attachments[1].url, options: [
                UNNotificationAttachmentOptionsThumbnailHiddenKey: true,
                UNNotificationAttachmentOptionsRevealActionTitleKey: "Show",
                UNNotificationAttachmentOptionsConcealActionTitleKey: "Hide",
            ])
        }
        mutable.attachments = [primary] + (expanded.map { [$0] } ?? [])
        return mutable
    }
}
