//
//  BackgroundRefreshLifecycleModifier.swift
//  FurAffinity
//
//  Created by Ceylo on 24/05/2026.
//

import Defaults
import SwiftUI

struct BackgroundRefreshLifecycleModifier: ViewModifier {
    // Not private: skipstone can't bridge a private @State/@Environment.
    @Environment(Model.self) var model
    @Environment(\.scenePhase) var scenePhase
    @State var didRequestNotificationAuthorization = false
    @State var notificationAuthorizationTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .onFirstAppear {
                recordOpen()
                Task { @MainActor in
                    await updateLatestFetchedNotificationIDsAfterAuthorization()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    recordOpen()
                    Task { @MainActor in
                        await updateLatestFetchedNotificationIDsAfterAuthorization()
                    }
                } else if newPhase == .background {
                    Defaults[.backgroundRefreshBudget].recordForegroundEnd(at: Date())
                    Task { @MainActor in
                        await updateLatestFetchedNotificationIDsAfterAuthorization()
                        BackgroundRefreshManager.schedule()
                    }
                }
            }
    }

    private func recordOpen() {
        Defaults[.backgroundRefreshBudget].profile.recordOpen(at: Date(), calendar: .current)
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
        // Only shown with a session, which the clearance let through.
        BackgroundRefreshManager.endChallengeOutage()
    }
}

extension View {
    func backgroundRefreshLifecycle() -> some View {
        modifier(BackgroundRefreshLifecycleModifier())
    }
}
