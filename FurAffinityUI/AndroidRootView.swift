//
//  AndroidRootView.swift
//  FurAffinityUI (Android)
//
//  Root of the Android app: the login flow until a session exists, then the shared
//  Followed feed driven by the shared `Model`. Tapping a card is still a stub —
//  porting submission detail and the `InAppNavigation` fan-out is a later step.
//

import SwiftUI
import FAKit

struct AndroidRootView: View {
    @State var session: (any FASession)?
    @State var model = Model()
    @State var navigationStream = NavigationStream()

    var body: some View {
        Group {
            if session != nil {
                NavigationStack {
                    AndroidSubmissionsFeedView()
                        .navigationTitle("Submissions")
                        .navigationDestination(for: FATarget.self) { target in
                            notPortedYet(target)
                        }
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
