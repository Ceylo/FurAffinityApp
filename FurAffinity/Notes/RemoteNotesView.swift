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
    
    var body: some View {
        PreviewableRemoteView<_, _, EmptyView>(
            url: FAURLs.notesInboxUrl,
            preloadedData: model.notePreviews,
            dataSource: { url in
                try await model.fetchNotePreviews()
            },
            view: { notes, updateHandler in
                NotesView(
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
