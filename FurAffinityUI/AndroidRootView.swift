//
//  AndroidRootView.swift
//  FurAffinityUI (Android)
//
//  Root of the Android app: the login flow until a session exists, then the shared
//  Followed feed driven by the shared `Model`, inside a `NavigationStack` fed by the
//  shared `NavigationStream` (same as iOS's LoggedInView). Pushed destinations come
//  from `view(for:)` in AndroidNavigationDestination.swift.
//

import SwiftUI
import FAKit

struct AndroidRootView: View {
    @State var session: (any FASession)?
    @State var model = Model()
    @State var navigationStream = NavigationStream()
    @State var path = [FATarget]()

    var body: some View {
        Group {
            if session != nil {
                NavigationStack(path: $path) {
                    AndroidSubmissionsFeedView()
                        .navigationTitle("Submissions")
                        .navigationDestination(for: FATarget.self) { target in
                            view(for: target)
                        }
                }
                .autorefreshingOnForeground {
                    await model.autorefreshIfNeeded()
                }
            } else {
                AndroidLoginView(onSession: { session = $0 })
            }
        }
        // Above the NavigationStack so it also covers pushed screens.
        .overlay(alignment: .top) {
            errorBanner
        }
        .environment(model)
        .environment(model.errorStorage)
        .environment(\.navigationStream, navigationStream)
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
