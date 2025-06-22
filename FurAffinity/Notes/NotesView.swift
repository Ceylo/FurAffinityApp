//
//  NotesView.swift
//  FurAffinity
//
//  Created by Ceylo on 09/04/2022.
//

import SwiftUI
import FAKit

struct NotesView: View {
    var notes: [FANotePreview]
    var sendNoteAction: (_ destinationUser: String, _ subject: String, _ message: String) async throws -> Void
    @State private var noteReplySession: NoteReplySession?
    
    var body: some View {
        List(notes) { preview in
            HStack {
                NavigationLink(value: FATarget.note(url: preview.noteUrl)) {
                    NoteItemView(notePreview: preview)
                }
            }
        }
        .listStyle(.plain)
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Notes")
        .swap(when: notes.isEmpty) {
            ScrollView {
                VStack(spacing: 10) {
                    Text("It's a bit empty in here.")
                        .font(.headline)
                    Text(markdown: "Messages from [\(FAURLs.notesInboxUrl.schemelessDisplayString)](\(FAURLs.notesInboxUrl)) will be displayed here.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    Text("You may pull to refresh.")
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
        .toolbar {
            Menu {
                Button {
                    noteReplySession = .init(defaultContents: .init())
                } label: {
                    Label("Send a Note", systemImage: "message")
                }
            } label: {
                ActionControl()
            }
            .noteReplySheet(on: $noteReplySession) { reply in
                try await sendNoteAction(reply.destinationUser, reply.subject, reply.text)
            }
        }
    }
}

#Preview {
    NavigationStack {
        NotesView(
            notes: OfflineFASession.default.notePreviews,
            sendNoteAction: { _, _, _ in }
        )
    }
}

#Preview {
    NavigationStack {
        NotesView(
            notes: OfflineFASession.empty.notePreviews,
            sendNoteAction: { _, _, _ in }
        )
    }
}
