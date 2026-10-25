//
//  BackgroundRefreshManager+Android.swift
//  FurAffinityUI (Android)
//
//  Android's hooks for the shared background refresh: a periodic JobScheduler job
//  (FABackgroundRefreshJobService.kt) runs it on a session built from the cookie jar
//  alone.
//
//  Unguarded on purpose — an Android substitution file must be, see
//  Android/docs/shared-sources.md § Rules for shared sources. The JNI inside is `canImport(Android)`-guarded and no-ops on Darwin.
//

import Foundation
import FAKit
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
        let minutes = Int64(BackgroundRefreshBudget.minimumRunInterval / 60)
        Task {
            let scheduled = await callBridgeOffPool("FANotificationBridge", fallback: false) { bridge in
                let ok: Bool? = try bridge.scheduleBackgroundRefresh(minutes)
                return ok == true
            }
            if scheduled {
                logger.info("Scheduled background refresh (every \(minutes) min)")
            } else {
                logger.error("Failed scheduling background refresh")
            }
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
                actions: [UNNotificationAction(identifier: showActionIdentifier, title: "Show", options: [])],
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

    /// Keeps a submission's thumbnail URL for Show.
    static func enrich(_ content: UNMutableNotificationContent, for record: PendingNotificationRecord) async -> UNNotificationContent {
        if let thumbnailURLString = record.thumbnailURLString {
            content.userInfo[thumbnailURLKey] = thumbnailURLString
        }
        return await communicationContent(content, author: record.author)
    }

    /// A general submission's clear image goes in hidden too, which makes it the expanded
    /// picture. A mature one keeps only its blurred image, and gets the Show button.
    static func attaching(_ attachments: [UNNotificationAttachment], to content: UNNotificationContent) -> UNNotificationContent {
        guard let mutable = content.mutableCopy() as? UNMutableNotificationContent, let primary = attachments.first else {
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
    /// thumbnail or a blurred one, both built as the first post built them. A Hide that can't
    /// blur drops the image rather than leave it clear.
    static func handleAction(_ response: UNNotificationResponse) async {
        let revealing: Bool
        switch response.actionIdentifier {
        case showActionIdentifier: revealing = true
        case hideActionIdentifier: revealing = false
        default: return
        }
        let request = response.notification.request
        guard let base = request.content.mutableCopy() as? UNMutableNotificationContent else {
            return
        }
        base.interruptionLevel = .passive
        base.categoryIdentifier = revealing ? revealedSubmissionCategoryIdentifier : hiddenSubmissionCategoryIdentifier
        base.attachments = []
        var content: UNNotificationContent = base
        // Downloaded when the notification was built, so this reads Kingfisher's cache.
        if let urlString = request.content.userInfo[thumbnailURLKey] as? String, let url = URL(string: urlString),
           let attachments = await submissionAttachment(thumbnailURL: url, needsBlur: !revealing) {
            content = attaching(attachments, to: base)
        } else {
            logger.error("No thumbnail to \(revealing ? "show" : "hide") for \(request.identifier)")
            if revealing {
                return
            }
        }
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: nil))
        } catch {
            logger.error("Could not \(revealing ? "show" : "hide") the thumbnail of \(request.identifier): \(error)")
        }
    }
}
