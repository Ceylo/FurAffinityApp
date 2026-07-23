//
//  AndroidRootView.swift
//  FurAffinityUI (Android)
//
//  Root of the Android app. Shows the login flow until a session exists, then a
//  placeholder confirming the logged-in user. Step 7 swaps the placeholder for
//  the shared LoggedInView / SubmissionsFeedView.
//

import SwiftUI
import FAKit

struct AndroidRootView: View {
    @State var session: OnlineFASession?

    var body: some View {
        Group {
            if let session {
                LoggedInPlaceholderView(session: session)
            } else {
                AndroidLoginView(onSession: { session = $0 })
            }
        }
        .task {
            logger.info("Android root view appeared")
            AndroidDefaultsRoundTrip.run()
        }
    }
}

struct LoggedInPlaceholderView: View {
    let session: OnlineFASession

    var body: some View {
        VStack(spacing: 16) {
            Text("Logged in")
                .font(.largeTitle)
            Text(session.displayUsername)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Feed comes next (step 7)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
