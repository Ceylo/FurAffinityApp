//
//  RemoteNoteView.swift
//  FurAffinity
//
//  Created by Ceylo on 25/04/2025.
//

import SwiftUI

struct RemoteNoteView: View {
    var url: URL
    // Not private: skipstone can't bridge a private @State/@Environment.
    @Environment(Model.self) var model
    
    var body: some View {
        PreviewableRemoteView<_, _, EmptyView>(
            url: url,
            dataSource: { try await model.session.unwrap().note(for: $0) },
            view: { note, updateHandler in
                NoteView(
                    note: note,
                    replyAction: { _, subject, text in
                        let session = try model.session.unwrap()
                        return try await session.sendNote(
                            apiKey: note.answerKey,
                            toUsername: note.author,
                            subject: subject,
                            message: text
                        )
                    }
                )
                .onAppear {
                    model.markNoteAsReadLocally(note)
                }
            }
        )
    }
}


#Preview {
    withAsync({ try await Model.demo }) {
        NavigationStack {
            RemoteNoteView(url: OfflineFASession.default.notePreviews[1].noteUrl)
        }
        //        .preferredColorScheme(.dark)
        .environment($0)
        .environment($0.errorStorage)
    }
}
