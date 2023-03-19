//
//  NotesView.swift
//  FurAffinity
//
//  Created by Ceylo on 09/04/2022.
//

import SwiftUI
import FAKit

extension FANotePreview: Identifiable {}

struct NotesView: View {
    @EnvironmentObject var model: Model
    @Binding var navigationStack: NavigationPath
    
    func refresh() async {
        await model.fetchNewNotePreviews()
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
        NavigationStack(path: $navigationStack) {
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
                .navigationDestination(for: FAURL.self) { nav in
                    view(for: nav)
                }
                .swap(when: notes.isEmpty) {
                    VStack(spacing: 10) {
                        Text("It's a bit empty in here.")
                            .font(.headline)
                        Text("Messages from your inbox in [www.furaffinity.net/msg/pms/](https://www.furaffinity.net/controls/switchbox/inbox/) will be displayed here.")
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
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
            NotesView(navigationStack: .constant(.init()))
                .environmentObject(Model.demo)
            
            NotesView(navigationStack: .constant(.init()))
                .environmentObject(Model.empty)
        }
        .preferredColorScheme(.dark)
    }
}
