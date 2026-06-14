//
//  BackgroundRefreshLifecycleModifier.swift
//  FurAffinity
//
//  Created by Ceylo on 24/05/2026.
//

import SwiftUI

private struct BackgroundRefreshLifecycleModifier: ViewModifier {
    @Environment(Model.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var didRequestNotificationAuthorization = false
    @State private var notificationAuthorizationTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onFirstAppear {
                Task { @MainActor in
                    await updateLatestFetchedNotificationIDsAfterAuthorization()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { @MainActor in
                        await updateLatestFetchedNotificationIDsAfterAuthorization()
                    }
                } else if newPhase == .background {
                    Task { @MainActor in
                        await updateLatestFetchedNotificationIDsAfterAuthorization()
                        BackgroundRefreshManager.schedule()
                    }
                }
            }
    }

    @MainActor
    private func requestNotificationAuthorizationIfNeeded() async {
        if didRequestNotificationAuthorization {
            return
        }

        if let notificationAuthorizationTask {
            await notificationAuthorizationTask.value
            return
        }

        let task = Task {
            await BackgroundRefreshManager.requestNotificationAuthorizationIfNeeded()
        }
        notificationAuthorizationTask = task
        await task.value
        didRequestNotificationAuthorization = true
        notificationAuthorizationTask = nil
    }

    @MainActor
    private func updateLatestFetchedNotificationIDsAfterAuthorization() async {
        await requestNotificationAuthorizationIfNeeded()
        BackgroundRefreshManager.updateLatestFetchedNotificationIDs(
            submissions: Array(model.submissionPreviews ?? []),
            notes: model.notePreviews[.inbox] ?? [],
            notifications: model.notificationPreviews
        )
        // The user is now in the app and has seen this content; drop any background
        // notifications still queued for posting. The watermark was just advanced to
        // the in-app state, so discarded items won't be rediscovered.
        BackgroundRefreshManager.discardPendingNotificationQueue()
    }
}

extension View {
    func backgroundRefreshLifecycle() -> some View {
        modifier(BackgroundRefreshLifecycleModifier())
    }
}
