//
//  StagedDeletionUndoSnackbar.swift
//  FurAffinity
//
//  Created by Ceylo on 29/09/2026.
//


import SwiftUI

/// The Undo snackbar for the model's staged deletion, and the commits that end it
/// early. A view of its own, so the feed body depends on neither.
struct StagedDeletionUndoSnackbar: View {
    // Not private: skipstone can't bridge a private @State/@Environment.
    @Environment(Model.self) var model
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        let count = model.stagedSubmissionPreviewsDeletion.count
        let isShown = count > 0
        UndoSnackbar(message: count > 1 ? "\(count) submissions deleted" : "Submission deleted") {
            model.undoStagedSubmissionPreviewsDeletion()
        }
        // Stays mounted so it can fade: `.transition` gets a hard cut on SkipUI.
        .opacity(isShown ? 1 : 0)
        .offset(y: isShown ? 0 : 16)
        // Not `withAnimation`: it marks the whole Compose frame on SkipUI.
        .animation(.easeInOut(duration: 0.25), value: isShown)
        .allowsHitTesting(isShown)
        .accessibilityHidden(!isShown)
        // A polite live region on Android, so TalkBack reads the snackbar as it appears;
        // only while shown, or it is read again as it fades out.
        .accessibilityAddTraits(isShown ? .updatesFrequently : [])
        // Undo can't be reached from the background, and the process may not outlive it.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                model.commitStagedSubmissionPreviewsDeletion()
            }
        }
        // Nor from a covered feed.
        .onDisappear {
            model.commitStagedSubmissionPreviewsDeletion()
        }
    }
}
