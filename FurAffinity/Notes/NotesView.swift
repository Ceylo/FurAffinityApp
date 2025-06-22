//
//  NotesView.swift
//  FurAffinity
//
//  Created by Ceylo on 09/04/2022.
//

import SwiftUI
import FAKit

extension NotesBox {
    var displayName: String {
        switch self {
        case .inbox:
            "Inbox"
        case .sent:
            "Sent"
        }
    }
    
    var systemImageName: String {
        switch self {
        case .inbox:
            "tray"
        case .sent:
            "paperplane"
        }
    }
}

struct NotesView: View {
    @Binding var displayedBox: NotesBox
    var notes: [FANotePreview]
    var sendNoteAction: (_ destinationUser: String, _ subject: String, _ message: String) async throws -> Void
    @State private var noteReplySession: NoteReplySession?
    
    @ToolbarContentBuilder
    var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack {
                Image(systemName: displayedBox.systemImageName)
                Text(displayedBox.displayName)
                    .font(.headline)
            }
        }

        ToolbarItem {
            Menu {
                Picker("Boxes", systemImage: "folder", selection: $displayedBox) {
                    Button {
                    } label: {
                        Label("Inbox", systemImage: "tray")
                    }
                    .tag(NotesBox.inbox)
                    
                    Button {
                    } label: {
                        Label("Sent", systemImage: "paperplane")
                    }
                    .tag(NotesBox.sent)
                }
                
                Divider()
                
                Button {
                    noteReplySession = .init(defaultContents: .init())
                } label: {
                    Label("Send a Note", systemImage: "message")
                }
            } label: {
                ActionControl()
            }
        }
    }
    
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
        .navigationTitle(displayedBox.displayName)
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
            toolbar
        }
        .noteReplySheet(on: $noteReplySession) { reply in
            try await sendNoteAction(reply.destinationUser, reply.subject, reply.text)
        }
    }
}

#Preview {
    NavigationStack {
        NotesView(
            displayedBox: .constant(NotesBox.inbox),
            notes: OfflineFASession.default.notePreviews,
            sendNoteAction: { _, _, _ in }
        )
    }
}

#Preview {
    NavigationStack {
        NotesView(
            displayedBox: .constant(NotesBox.inbox),
            notes: OfflineFASession.empty.notePreviews,
            sendNoteAction: { _, _, _ in }
        )
    }
}
