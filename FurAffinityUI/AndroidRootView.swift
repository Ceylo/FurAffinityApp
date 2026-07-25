//
//  AndroidRootView.swift
//  FurAffinityUI (Android)
//
//  Root of the Android app: the login flow until a session exists, then the ported
//  tabs driven by the shared `Model`, mirroring `LoggedInView` on iOS. Tabs are added
//  as screens are ported. Tapping a feed card is still a stub — porting submission
//  detail and the `InAppNavigation` fan-out is a later step.
//

import SwiftUI
import FAKit

struct AndroidRootView: View {
    @State var session: (any FASession)?
    @State var model = Model()
    @State var navigationStream = NavigationStream()
    @State var selectedTab: Tab = .submissions

    enum Tab {
        case submissions
        case settings
    }

    var body: some View {
        Group {
            if session != nil {
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        AndroidSubmissionsFeedView()
                            .navigationTitle("Submissions")
                            .navigationDestination(for: FATarget.self) { target in
                                notPortedYet(target)
                            }
                    }
                    // SkipUI maps a fixed set of SF Symbols onto Material icons and
                    // draws a warning triangle for the rest, so these two don't match
                    // LoggedInView's `rectangle.grid.2x2` / `slider.horizontal.3`.
                    .tabItem {
                        Label("Submissions", systemImage: "list.bullet")
                    }
                    .tag(Tab.submissions)

                    NavigationStack {
                        // Stands in for SettingsView until the rest of its surface is
                        // ported; on iOS this is a screen pushed from Settings.
                        NotificationSettingsView()
                            .navigationDestination(for: FATarget.self) { target in
                                notPortedYet(target)
                            }
                    }
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tag(Tab.settings)
                }
            } else {
                AndroidLoginView(onSession: { session = $0 })
            }
        }
        .environment(model)
        .environment(model.errorStorage)
        .environment(\.navigationStream, navigationStream)
        .task(id: session?.username) {
            await connect()
        }
        // Logging out clears the model's session; drop ours too so the login screen
        // comes back. Only fires on a change, so the nil `model.session` this view
        // starts with — before `connect()` has run — doesn't bounce it.
        .onChange(of: model.session == nil) { _, hasNoSession in
            if hasNoSession {
                session = nil
            }
        }
    }

    private func notPortedYet(_ target: FATarget) -> some View {
        Centered {
            Text("This screen isn't ported to Android yet.")
                .foregroundStyle(.secondary)
        }
    }

    private func connect() async {
        guard let session, model.session == nil else { return }
        logger.info("Connecting model to session for \(session.username)")
        await storeLocalizedError(in: model.errorStorage, action: "Sign In", webBrowserURL: nil) {
            try await model.setSession(session)
        }
    }
}
