//
//  ForegroundAutorefresh.swift
//  FurAffinity
//
//  Created by Ceylo on 11/08/2026.
//

import SwiftUI

/// Runs `action` each time the app comes back to the foreground.
///
/// `scenePhase` rather than `willEnterForegroundNotification` so one source works on
/// Android too. The `.background` filter keeps fidelity with that notification: both
/// platforms also pass through `.inactive` for transient interruptions (Control Centre,
/// a permission dialog) without ever backgrounding.
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
