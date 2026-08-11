//
//  ForegroundAutorefresh.swift
//  FurAffinity
//
//  Created by Ceylo on 11/08/2026.
//

import SwiftUI

/// Runs `action` each time the app comes back to the foreground.
///
/// Driven by `scenePhase` rather than `UIApplication.willEnterForegroundNotification`
/// so the same source works on Android, where Skip marks that notification unavailable
/// and points at `ScenePhase` instead: there `EnvironmentValues.scenePhase` reads
/// `UIApplication.shared.applicationState`, a Compose state fed by the Activity
/// lifecycle (`ON_RESUME` → `.active`, `ON_STOP` → `.background`).
///
/// The `.background` filter is what keeps fidelity with the notification: both
/// platforms also pass through `.inactive` for transient interruptions — Control
/// Centre, a permission dialog, the notification shade — without ever backgrounding,
/// and the notification never fired for those.
struct ForegroundAutorefresh: ViewModifier {
    // Internal, not private: a bridged view's @Environment must be.
    @Environment(\.scenePhase) var scenePhase
    var action: @MainActor () async -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { oldPhase, newPhase in
                guard oldPhase == .background, newPhase != .background else { return }
                Task { await action() }
            }
    }
}

extension View {
    /// Runs `action` whenever the app returns to the foreground.
    func autorefreshingOnForeground(_ action: @escaping @MainActor () async -> Void) -> some View {
        modifier(ForegroundAutorefresh(action: action))
    }
}
