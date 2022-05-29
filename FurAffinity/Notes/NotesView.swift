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
    @State private var notePreviews = [FANotePreview]()
    @State private var lastRefreshDate = Date()
    
    func refresh() async {
        notePreviews = await model.session?.notePreviews() ?? []
        lastRefreshDate = Date()
    }
    
    func autorefreshIfNeeded() {
        let secondsSinceLastRefresh = -lastRefreshDate.timeIntervalSinceNow
        guard secondsSinceLastRefresh > 60 else { return }
        
        Task {
            await refresh()
        }
    }
    
    var body: some View {
        NavigationView {
            List(notePreviews) { preview in
                NavigationLink(destination: NoteView(notePreview: preview, noteProvider: {
                    await model.session?.note(for: preview)
                })) {
                    NoteItemView(notePreview: preview)
                }
            }
            .listStyle(.plain)
            .navigationBarTitleDisplayMode(.inline)
        }
        .refreshable {
            await refresh()
        }
        .task {
            await refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            autorefreshIfNeeded()
        }
    }
}

struct NotesView_Previews: PreviewProvider {
    static var previews: some View {
        NotesView()
            .environmentObject(Model.demo)
            .preferredColorScheme(.dark)
    }
}
