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

    /// A mature submission's notification starts blurred, in this category; its Show
    /// button re-adds it revealed, in the other, whose Hide button blurs it again. iOS shows
    /// the clear image on a long-press instead, but Android expands the top notification on
    /// its own.
    private static let hiddenSubmissionCategoryIdentifier = "fa.submission.hidden"
    private static let revealedSubmissionCategoryIdentifier = "fa.submission.revealed"
    private static let showActionIdentifier = "fa.show"
    private static let hideActionIdentifier = "fa.hide"
    /// The submission thumbnail Show reveals, fetched again from Kingfisher's cache.
    private static let thumbnailURLKey = "fa.thumbnail.url"

    static func registerNotificationCategories() {
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(
                identifier: hiddenSubmissionCategoryIdentifier,
                actions: [UNNotificationAction(identifier: showActionIdentifier, title: "Show", options: [.authenticationRequired])],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: revealedSubmissionCategoryIdentifier,
                actions: [UNNotificationAction(identifier: hideActionIdentifier, title: "Hide", options: [])],
                intentIdentifiers: [],
                options: []
            ),
        ])
    }

    /// Attaches the author's avatar, which becomes the large icon, unless a submission
    /// thumbnail will take that place, whose URL is kept for Show.
    static func enrich(_ content: UNMutableNotificationContent, for record: PendingNotificationRecord) async -> UNNotificationContent {
        if let thumbnailURLString = record.thumbnailURLString {
            content.userInfo[thumbnailURLKey] = thumbnailURLString
            return content
        }
        guard let url = FAURLs.avatarUrl(for: record.author) else {
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

    /// A general submission's clear image goes in hidden too, which makes it the expanded
    /// picture. A mature one keeps only its blurred image, and gets the Show button.
    static func attaching(_ attachments: [UNNotificationAttachment], to content: UNNotificationContent) -> UNNotificationContent {
        guard let mutable = content as? UNMutableNotificationContent, let primary = attachments.first else {
            return content
        }
        if attachments.dropFirst().contains(where: { $0.identifier == "clear" }) {
            mutable.attachments = [primary]
            mutable.categoryIdentifier = hiddenSubmissionCategoryIdentifier
        } else {
            mutable.attachments = [primary] + expandedCopy(of: primary)
        }
        return mutable
    }

    private static func expandedCopy(of attachment: UNNotificationAttachment) -> [UNNotificationAttachment] {
        guard let expanded = try? UNNotificationAttachment(identifier: "expanded", url: attachment.url, options: [UNNotificationAttachmentOptionsThumbnailHiddenKey: true]) else {
            return []
        }
        return [expanded]
    }

    /// Answers Show and Hide by adding the notification again, silently, with the clear
    /// thumbnail or a blurred one, both built as the first post built them. Returns whether
    /// `response` was one of them.
    static func handleAction(_ response: UNNotificationResponse) async -> Bool {
        let revealing: Bool
        switch response.actionIdentifier {
        case showActionIdentifier: revealing = true
        case hideActionIdentifier: revealing = false
        default: return false
        }
        let request = response.notification.request
        // Downloaded when the notification was built, so this reads Kingfisher's cache.
        guard let urlString = request.content.userInfo[thumbnailURLKey] as? String, let url = URL(string: urlString),
              let attachments = await submissionAttachment(thumbnailURL: url, needsBlur: !revealing) else {
            logger.error("No thumbnail to \(revealing ? "show" : "hide") for \(request.identifier)")
            return true
        }
        let content = UNMutableNotificationContent()
        content.title = request.content.title
        content.body = request.content.body
        content.userInfo = request.content.userInfo
        content.interruptionLevel = .passive
        let attached = attaching(attachments, to: content)
        if revealing, let mutable = attached as? UNMutableNotificationContent {
            mutable.categoryIdentifier = revealedSubmissionCategoryIdentifier
        }
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: request.identifier, content: attached, trigger: nil))
        } catch {
            logger.error("Could not \(revealing ? "show" : "hide") the thumbnail of \(request.identifier): \(error)")
        }
        return true
    }
}
