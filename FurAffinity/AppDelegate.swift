//
//  AppDelegate.swift
//  FurAffinity
//
//  Created by Ceylo on 25/06/2026.
//

import UIKit

/// Holds the currently-allowed orientation mask. The Info.plist widens the
/// iPhone ceiling to include landscape; this gate decides what's actually live
/// at any moment so the app stays portrait everywhere except the story reader.
@MainActor
final class OrientationGate {
    static let shared = OrientationGate()

    var allowsLandscape = false

    var mask: UIInterfaceOrientationMask {
        allowsLandscape ? .allButUpsideDown : .portrait
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        // iPad is laid out for every orientation; only the iPhone is gated.
        guard UIDevice.current.userInterfaceIdiom == .phone else { return .all }
        return MainActor.assumeIsolated { OrientationGate.shared.mask }
    }
}

extension UIWindowScene {
    /// The first foreground-active window scene, used to drive geometry updates.
    static var active: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
}

/// Opens/closes the landscape gate and asks UIKit to honor it. iPhone-only;
/// a no-op on iPad (which already rotates freely).
@MainActor
enum DeviceOrientationControl {
    static func enableLandscape() {
        setLandscape(true)
    }

    static func resetToPortrait() {
        setLandscape(false)
    }

    private static func setLandscape(_ enabled: Bool) {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        OrientationGate.shared.allowsLandscape = enabled

        guard let scene = UIWindowScene.active else { return }
        // When disabling, force back to portrait; when enabling, let UIKit honor
        // the current tilt by requesting the full allowed mask.
        let mask: UIInterfaceOrientationMask = enabled ? .allButUpsideDown : .portrait
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
            logger.error("Orientation geometry update failed: \(error)")
        }
        scene.keyWindow?.rootViewController?
            .setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}
