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
    
    func refresh() async {
        await model.fetchNotePreviews()
    }
    
    func autorefreshIfNeeded() {
        if let lastRefreshDate = model.lastNotePreviewsFetchDate {
            let secondsSinceLastRefresh = -lastRefreshDate.timeIntervalSinceNow
            guard secondsSinceLastRefresh > Model.autorefreshDelay else { return }
        }
        
        Task {
            await refresh()
        }
    }
    
    var body: some View {
        Group {
            if let notes = model.notePreviews {
                List(notes) { preview in
                    HStack {
                        NavigationLink(value: FAURL(with: preview.noteUrl)) {
                            NoteItemView(notePreview: preview)
                        }
                    }
                }
                .listStyle(.plain)
                .navigationBarTitleDisplayMode(.inline)
                .navigationTitle("Notes")
                .toolbar(.hidden, for: .navigationBar)
                .swap(when: notes.isEmpty) {
                    VStack(spacing: 10) {
                        Text("It's a bit empty in here.")
                            .font(.headline)
                        Text(markdown: "Messages from [\(FAURLs.notesInboxUrl.schemelessDisplayString)](\(FAURLs.notesInboxUrl)) will be displayed here.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            } else {
                ProgressView()
            }
        }
        .refreshable {
            await refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            autorefreshIfNeeded()
        }
    }
}

struct NotesView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NotesView()
                .environmentObject(Model.demo)
            
            NotesView()
                .environmentObject(Model.empty)
        }
        .preferredColorScheme(.dark)
    }
}
