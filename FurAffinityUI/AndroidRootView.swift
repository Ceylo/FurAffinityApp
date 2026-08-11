//
//  AndroidRootView.swift
//  FurAffinityUI (Android)
//
//  Root of the Android app: the login flow until a session exists, then the ported
//  tabs driven by the shared `Model`, mirroring `LoggedInView` on iOS. Tabs are added
//  as screens are ported. The Submissions tab is a `NavigationStack` fed by the shared
//  `NavigationStream`; pushed destinations come from `view(for:)` in
//  AndroidNavigationDestination.swift.
//

import SwiftUI
import FAKit

struct AndroidRootView: View {
    @State var session: (any FASession)?
    @State var model = Model()
    @State var navigationStream = NavigationStream()
    @State var path = [FATarget]()
    @State var selectedTab: Tab = .submissions

    enum Tab {
        case submissions
        case settings
    }

    var body: some View {
        ZStack {
            if session != nil {
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
            } else {
                AndroidLoginView(onSession: { session = $0 })
            }

            // The app's long-lived WebView, mirroring RootView's hidden
            // FAChallengeView on iOS: it holds the User-Agent `cf_clearance` is
            // bound to and serves FAHTTPDataSource's challenge fallback, so it has
            // to stay mounted for the whole session — see FAWebSession.
            FAWebSessionView()
        }
        // Above the TabView so it also covers pushed screens.
        .overlay(alignment: .top) {
            errorBanner
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

    private func connect() async {
        guard let session, model.session == nil else { return }
        logger.info("Connecting model to session for \(session.username)")
        await storeLocalizedError(in: model.errorStorage, action: "Sign In", webBrowserURL: nil) {
            try await model.setSession(session)
        }
    }
}
