//
//  NotesView.swift
//  FurAffinity
//
//  Created by Ceylo on 09/04/2022.
//

import SwiftUI
import FAKit

struct RemoteNotesView: View {
    @EnvironmentObject var model: Model
    
    @State private var sourceUrl = FAURLs.notesInboxUrl
    @State private var displayedBox: NotesBox = .inbox
    
    var body: some View {
        PreviewableRemoteView<_, _, EmptyView>(
            url: sourceUrl,
            preloadedData: model.inboxNotePreviews,
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
    NavigationStack {
        RemoteNotesView()
    }
    .environmentObject(Model.demo)
}

#Preview {
    NavigationStack {
        RemoteNotesView()
    }
    .environmentObject(Model.empty)
}
