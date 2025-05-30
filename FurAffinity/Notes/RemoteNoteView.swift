//
//  RemoteNoteView.swift
//  FurAffinity
//
//  Created by Ceylo on 25/04/2025.
//

import SwiftUI

struct RemoteNoteView: View {
    var url: URL
    @EnvironmentObject var model: Model
    
    var body: some View {
        PreviewableRemoteView<_, _, EmptyView>(
            url: url,
            dataSource: { await model.session?.note(for: $0) },
            view: { note, updateHandler in
                NoteView(
                    note: note,
                    replyAction: { text in
                        guard let session = model.session else {
                            return false
                        }
                        
                        return await session.sendNote(
                            apiKey: note.answerKey,
                            toUsername: note.author,
                            subject: note.title,
                            message: text + note.answerPlaceholderMessage
                        )
                    }
                )
            }
        )
    }
}


#Preview {
    NavigationStack {
        RemoteNoteView(url: OfflineFASession.default.notePreviews[1].noteUrl)
    }
//        .preferredColorScheme(.dark)
        .environmentObject(Model.demo)
}
