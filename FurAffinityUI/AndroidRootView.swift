//
//  AndroidRootView.swift
//  FurAffinityUI (Android)
//
//  Root of the Android app, mirroring iOS's `RootView`: the shared `HomeView` until
//  a session exists, then the ported tabs — which stand in for `LoggedInView` and
//  grow as screens are ported. The Submissions tab is a `NavigationStack` fed by the
//  shared `NavigationStream`; pushed destinations come from `view(for:)` in
//  AndroidNavigationDestination.swift.
//
//  HomeView owns the session on both platforms (it calls `model.setSession`), so
//  this view only reads `model.session` — including for logout, which SettingsView
//  performs by setting it back to nil.
//

import SwiftUI
import FAKit

struct AndroidRootView: View {
    @State var model = Model()
    @State var navigationStream = NavigationStream()
    @State var path = [FATarget]()
    @State var selectedTab: Tab = .submissions
    // Mirrors of the coordinator's two stage flags. iOS's RootView observes the
    // coordinator itself, but Skip's Compose bridge doesn't see changes to an
    // @Observable declared in another module, so the stages are driven from
    // local state fed by `onStateChange` below.
    @State var challengePending = false
    @State var challengeBackgroundPending = false

    enum Tab {
        case submissions
        case settings
    }

    var body: some View {
        ZStack {
            // The app's long-lived WebView, mirroring RootView's hidden
            // FAChallengeView on iOS: it holds the User-Agent `cf_clearance` is
            // bound to and serves FAHTTPDataSource's challenge fallback, so it has
            // to stay mounted for the whole session — see FAWebSession.
            //
            // It sits at the *bottom* of the stack at full size, hidden by the
            // opaque background above rather than by being shrunk or faded: it has
            // to keep rendering to clear a Cloudflare challenge (see
            // FAWebSessionView).
            FAWebSessionView()

            // Stage 1 of the two-stage flow: a challenge view for the passive
            // resolution most managed challenges do without a human. Kept below
            // the opaque background for the same reason as FAWebSessionView — it
            // has to lay out and render at full size to solve anything — and it
            // escalates to the sheet only when Cloudflare says the challenge is
            // interactive, or when the coordinator's safety timeout expires.
            if challengeBackgroundPending {
                FAChallengeView(
                    onResolved: { CloudflareChallengeCoordinator.shared.markResolved() },
                    onInteractionRequired: { CloudflareChallengeCoordinator.shared.markInteractionRequired() }
                )
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }

            Color(.systemBackground)
                .ignoresSafeArea()

            if model.session == nil {
                HomeView()
                    // Entry point for driving ported screens on the emulator without
                    // solving a Cloudflare challenge, which needs a real click in the
                    // emulator window. Gated on `android:debuggable` rather than
                    // `#if DEBUG`: skipstone skips those blocks when it generates the
                    // view bridge, so a compile-time fence here would be inert. FA
                    // image URLs still need the WebView's clearance, so images show
                    // placeholders in this mode.
                    .overlay(alignment: .top) {
                        if AndroidAppInfo.isDebuggable {
                            Button("Continue offline (debug)") {
                                Task {
                                    await storeLocalizedError(in: model.errorStorage, action: "Sign In", webBrowserURL: nil) {
                                        try await model.setSession(OfflineFASession.default)
                                    }
                                }
                            }
                            .font(.footnote)
                        }
                    }
            } else {
                TabView(selection: $selectedTab) {
                    NavigationStack(path: $path) {
                        AndroidSubmissionsFeedView()
                            .navigationTitle("Submissions")
                            .navigationDestination(for: FATarget.self) { target in
                                view(for: target)
                            }
                    }
                    // SkipUI maps a fixed set of SF Symbols onto Material icons and
                    // draws a warning triangle for the rest, so these two don't match
                    // LoggedInView's `rectangle.grid.2x2` / `slider.horizontal.3`.
                    .tabItem {
                        Label("Submissions", systemImage: "list.bullet")
                    }
                    .tag(Tab.submissions)

                    // SettingsView brings its own NavigationStack, same as on iOS,
                    // and has no FATarget destinations.
                    SettingsView()
                        .tabItem {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .tag(Tab.settings)
                }
            }
        }
        // Above the TabView so it also covers pushed screens.
        .overlay(alignment: .top) {
            errorBanner
        }
        // Stage 2: the challenge needs a human. Dismissing without solving it
        // fails the parked request rather than leaving it hanging.
        .sheet(
            isPresented: Binding(
                get: { challengePending },
                set: { isPresented in
                    if !isPresented && challengePending {
                        CloudflareChallengeCoordinator.shared.markFailed()
                    }
                }
            )
        ) {
            FAChallengeView(
                onResolved: { CloudflareChallengeCoordinator.shared.markResolved() }
            )
        }
        .task {
            // FAKit's defaults can't reach either of these on Android: there is
            // no UIApplication, and the cookies live in the WebView's own jar.
            CloudflareChallengeCoordinator.shared.configure(
                isInBackground: { false },
                cookieProvider: { FAWebSession.shared.lastKnownAuthCookies },
                // Generous next to iOS's 8 s: a managed challenge on the emulator
                // takes 15-20 s to clear itself, and escalating sooner would put a
                // sheet in front of the user that was about to go away by itself.
                safetyTimeout: .seconds(25)
            )
            CloudflareChallengeCoordinator.shared.onStateChange = {
                let coordinator = CloudflareChallengeCoordinator.shared
                challengePending = coordinator.pending
                challengeBackgroundPending = coordinator.backgroundResolutionPending
            }
        }
        .environment(model)
        .environment(model.errorStorage)
        .environment(\.navigationStream, navigationStream)
        // Gap: an event raised from the Settings tab pushes onto the Submissions
        // stack without selecting that tab, so the push isn't visible until the
        // user switches. iOS's LoggedInView picks a stack per tab; nothing in
        // Settings sends navigation events yet.
        .onChange(of: navigationStream.latest) { _, event in
            guard let event else { return }
            path.append(event.target)
        }
        .environment(\.openURL, OpenURLAction { url in
            // Only the app scheme is ours. Rich text runs its links through
            // `convertingLinksForInAppNavigation()`, which rewrites the navigable ones
            // to that scheme; `FATarget` maps them back.
            //
            // Matching on `FATarget(with:)` alone would be wrong: it normalises the
            // scheme to https before matching, so a *plain* FA URL matches too — and
            // SkipUI routes every `Link` through this action, so "Open in Web Browser"
            // would push another copy of the page it is trying to leave.
            guard url.scheme == appNavigationScheme, let target = FATarget(with: url) else {
                return .systemAction
            }
            navigationStream.send(target)
            return .handled
        })
        .autorefreshingOnForeground {
            await model.autorefreshIfNeeded()
        }
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let error = model.errorStorage.error {
            VStack(spacing: 4) {
                Text(error.relatedAction ?? "Error")
                    .font(.headline)
                Text(error.errorDescription ?? "Something went wrong.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                Button("Dismiss") { model.errorStorage.error = nil }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.thinMaterial)
        }
    }
}
