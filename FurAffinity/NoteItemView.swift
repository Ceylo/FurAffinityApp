//
//  NoteItemView.swift
//  FurAffinity
//
//  Created by Ceylo on 09/04/2022.
//

import SwiftUI
import FAKit

struct NoteItemView: View {
    @EnvironmentObject var model: Model
    var notePreview: FANotePreview
    @State private var avatarUrl: URL?
    
    var body: some View {
        HStack {
            AvatarView(avatarUrl: avatarUrl)
                .frame(width: 42, height: 42)
                .task {
                    avatarUrl = await model.session?.avatarUrl(for: notePreview.author)
                }
            
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    if notePreview.unread {
                        Circle()
                            .frame(width: 10, height: 10)
                            .foregroundColor(.accentColor)
                    }
                    
                    Text(notePreview.title)
                        .font(.headline)
                }
                
                HStack {
                    Text(notePreview.displayAuthor)
                    Spacer()
                    Text(notePreview.datetime)
                }
                .foregroundStyle(.secondary)
                .font(.subheadline)
            }
        }
    }
}

struct NoteItemView_Previews: PreviewProvider {
    static var previews: some View {
        NoteItemView(notePreview: OfflineFASession.default.notePreviews[0])
            .previewLayout(.sizeThatFits)
            .preferredColorScheme(.dark)
            .environmentObject(Model.demo)
    }
}
