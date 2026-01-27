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
        model.inboxNotePreviews ?? []
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
                    notes: notes,
                    sendNoteAction: { destinationUser, subject, message in
                        let session = try model.session.unwrap()
                        try await session.sendNote(
                            toUsername: destinationUser,
                            subject: subject,
                            message: message
                        )
                    }, moveNotesAction: { notes, box in
                        Task {
                            await storeLocalizedError(in: errorStorage, action: "Move Note to \(box.displayName)", webBrowserURL: nil) {
                                let session = try model.session.unwrap()
                                let updated = try await session.moveNotes(notes, to: box)
                                withAnimation {
                                    updateHandler.update(with: updated)
                                }
                            }
                        }
                    }
                )
                .onChange(of: cachedInboxNotePreview) { oldValue, newValue in
                    guard displayedBox == .inbox else { return }
                    updateHandler.update(with: newValue)
                }
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
