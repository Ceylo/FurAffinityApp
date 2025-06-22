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
        .toolbar(.hidden, for: .navigationBar)
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
    }
}

#Preview {
    NavigationStack {
        NotesView(notes: OfflineFASession.default.notePreviews)
    }
}

#Preview {
    NavigationStack {
        NotesView(notes: OfflineFASession.empty.notePreviews)
    }
}
