//
//  RemoteNoteView.swift
//  FurAffinity
//
//  Created by Ceylo on 25/04/2025.
//

import SwiftUI

struct RemoteNoteView: View {
    var url: URL
    @Environment(Model.self) private var model
    
    var body: some View {
        PreviewableRemoteView<_, _, EmptyView>(
            url: url,
            dataSource: { try await model.session.unwrap().note(for: $0) },
            view: { note, updateHandler in
                NoteView(
                    note: note,
                    replyAction: { destinationUser, subject, text in
                        let session = try model.session.unwrap()
                        assert(destinationUser == note.author)
                        
                        return try await session.sendNote(
                            apiKey: note.answerKey,
                            toUsername: note.author,
                            subject: subject,
                            message: text
                        )
                    }
                )
                .onAppear {
                    model.markInboxNoteAsRead(note)
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
    }
}
