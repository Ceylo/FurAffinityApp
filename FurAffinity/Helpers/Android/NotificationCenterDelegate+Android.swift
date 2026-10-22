//
//  NotificationCenterDelegate+Android.swift
//  FurAffinityUI (Android)
//

import Foundation
import SwiftUI

/// Receives notification taps and hands their deep link to `NotificationCoordinator`,
/// as the iOS delegate does. SkipUI calls `didReceive` from the activity's launch or
/// new intent, holding a tap that arrives before the delegate is set.
final class NotificationCenterDelegate: UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationCenterDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let urlString = NotificationCoordinator.deepLinkURLString(fromUserInfo: response.notification.request.content.userInfo)
        await NotificationCoordinator.shared.setPendingDeepLink(fromURLString: urlString)
    }
}
