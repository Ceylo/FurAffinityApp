//
//  NotesView.swift
//  FurAffinity
//
//  Created by Ceylo on 09/04/2022.
//

import SwiftUI
import FAKit

struct NotesView: View {
    @EnvironmentObject var model: Model
    
    var body: some View {
        Group {
            if let notes = model.notePreviews {
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
            } else {
                ProgressView()
            }
        }
        .refreshable {
            await model.fetchNotePreviews()
        }
    }
}

#Preview {
    NavigationStack {
        NotesView()
    }
    .environmentObject(Model.demo)
}

#Preview {
    NavigationStack {
        NotesView()
    }
    .environmentObject(Model.empty)
}
