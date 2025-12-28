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
                    }
                )
                .onChange(of: cachedInboxNotePreview) { oldValue, newValue in
                    guard displayedBox == .inbox else { return }
                    updateHandler.update(with: newValue)
                }
            }
        )
        .onChange(of: displayedBox) { oldValue, newValue in
            switch newValue {
            case .inbox:
                sourceUrl = FAURLs.notesInboxUrl
            case .sent:
                sourceUrl = FAURLs.notesSentUrl
            }
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
