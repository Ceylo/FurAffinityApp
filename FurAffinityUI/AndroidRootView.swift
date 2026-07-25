//
//  AndroidRootView.swift
//  FurAffinityUI (Android)
//
//  Root of the Android app: the login flow until a session exists, then the shared
//  Followed feed driven by the shared `Model`, inside a `NavigationStack` whose path
//  *is* the `NavigationStream` (Android has no Combine, see FALink.swift). Pushed
//  destinations come from `view(for:)` in AndroidNavigationDestination.swift.
//

import SwiftUI
import FAKit

struct AndroidRootView: View {
    @State var session: (any FASession)?
    @State var model = Model()
    @State var navigationStream = NavigationStream()

    var body: some View {
        @Bindable var navigation = navigationStream

        Group {
            if session != nil {
                NavigationStack(path: $navigation.path) {
                    AndroidSubmissionsFeedView()
                        .navigationTitle("Submissions")
                        .navigationDestination(for: FATarget.self) { target in
                            view(for: target)
                        }
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
