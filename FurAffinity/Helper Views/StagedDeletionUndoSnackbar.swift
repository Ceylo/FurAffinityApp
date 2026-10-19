//
//  StagedDeletionUndoSnackbar.swift
//  FurAffinity
//
//  Created by Ceylo on 29/09/2026.
//


import SwiftUI

/// The Undo snackbar for a `StagedDeletion`, and the commits that end it early.
struct StagedDeletionUndoSnackbar: View {
    var count: Int
    var message: String
    var onUndo: () -> Void
    var onCommit: () -> Void
    // Not private: skipstone can't bridge a private @State/@Environment.
    @Environment(\.scenePhase) var scenePhase

    var body: some View {
        let isShown = count > 0
        UndoSnackbar(message: message, onUndo: onUndo)
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
                onCommit()
            }
        }
        // Nor from a covered list.
        .onDisappear {
            onCommit()
        }
    }
}

extension StagedDeletion {
    func undoSnackbar(message: (_ count: Int) -> String) -> StagedDeletionUndoSnackbar {
        StagedDeletionUndoSnackbar(
            count: staged.count,
            message: message(staged.count),
            onUndo: undo,
            onCommit: { self.commit() }
        )
    }
}
