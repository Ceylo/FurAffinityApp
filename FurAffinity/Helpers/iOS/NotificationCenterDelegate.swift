//
//  NotificationCenterDelegate.swift
//  FurAffinity
//

#if !FA_SKIP_MODULE

import Foundation
import UserNotifications

/// Receives notification taps and hands their deep link to `NotificationCoordinator`.
///
/// There is no SwiftUI-native API for notification responses, but we don't need
/// a `UIApplicationDelegateAdaptor`: this object is set as
/// `UNUserNotificationCenter`'s delegate at launch.
final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationCenterDelegate()

    // Completion-handler delegate variant. We call `completionHandler()`
    // synchronously and immediately, and never touch `@MainActor` state inline:
    // the system finishes handling the response (and the foreground transition
    // on a tap) only once this method returns. The async variant returned only
    // after an `await` hop onto the (possibly busy) main actor, which delayed
    // the implicit completion and could keep the app from foregrounding. Here
    // the main-actor work is handed off to a detached `Task` instead.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        // Extract the Sendable String off-actor; do NOT block on a main-actor hop here.
        let urlString = NotificationCoordinator.deepLinkURLString(fromUserInfo: response.notification.request.content.userInfo)
        if let urlString {
            Task { @MainActor in
                NotificationCoordinator.shared.setPendingDeepLink(fromURLString: urlString)
            }
        }
        // Signal completion right away so the system finishes foregrounding the app.
        completionHandler()
    }
}

#endif
