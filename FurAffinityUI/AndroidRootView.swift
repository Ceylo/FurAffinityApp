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
                // Phase B: real Coil-backed feed images stand in for the feed (step 7).
                AndroidFeedPreview(session: session)
            } else {
                AndroidLoginView(onSession: { session = $0 })
            }
        }
        .task {
            logger.info("Android root view appeared")
        }
    }
}
