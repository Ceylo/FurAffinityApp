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
                NoteView(note: note)
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
