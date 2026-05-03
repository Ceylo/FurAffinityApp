//
//  NotesView.swift
//  FurAffinity
//
//  Created by Ceylo on 09/04/2022.
//

import SwiftUI
import FAKit

struct RemoteNotesView: View {
    @Environment(Model.self) private var model
    @Environment(ErrorStorage.self) private var errorStorage
    
    @State private var sourceUrl = FAURLs.notesInboxUrl
    @State private var displayedBox: NotesBox = .inbox
    
    var cachedInboxNotePreview: [FANotePreview] {
        model.notePreviews[displayedBox] ?? []
    }
    
    var body: some View {
        PreviewableRemoteView<_, _, EmptyView>(
            url: sourceUrl,
            preloadedData: cachedInboxNotePreview,
            dataSource: { url in
                try await model.fetchNotePreviews(from: displayedBox)
            },
            view: { notes, updateHandler in
                NotesView(
                    displayedBox: $displayedBox,
                    notes: cachedInboxNotePreview,
                    sendNoteAction: { destinationUser, subject, message in
                        let session = try model.session.unwrap()
                        try await session.sendNote(
                            toUsername: destinationUser,
                            subject: subject,
                            message: message
                        )
                    }, moveNotesAction: { notes, destinationBox in
                        Task {
                            await storeLocalizedError(in: errorStorage, action: "Move Note to \(destinationBox.displayName)", webBrowserURL: nil) {
                                try await model.moveNotes(notes, from: displayedBox, to: destinationBox)
                            }
                        }
                    }, markUnreadAction: { notes in
                        Task {
                            await storeLocalizedError(in: errorStorage, action: "Mark Unread", webBrowserURL: nil) {
                                try await model.markNotesAsUnread(notes, in: displayedBox)
                            }
                        }
                    }
                )
            }
        )
        .onChange(of: displayedBox) { _, newValue in
            sourceUrl = newValue.url
        }
    }
}

#Preview {
    withAsync({ try await Model.demo }) {
        NavigationStack {
            RemoteNotesView()
        }
        .environment($0)
        .environment($0.errorStorage)
    }
}

#Preview {
    withAsync({ try await Model.empty }) {
        NavigationStack {
            RemoteNotesView()
        }
        .environment($0)
        .environment($0.errorStorage)
    }
}
