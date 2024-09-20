//
//  NoteItemView.swift
//  FurAffinity
//
//  Created by Ceylo on 09/04/2022.
//

import SwiftUI
import FAKit

struct NoteItemView: View {
    var notePreview: FANotePreview
    
    var body: some View {
        HStack(alignment: .top) {
            AvatarView(avatarUrl: FAURLs.avatarUrl(for: notePreview.author))
                .frame(width: 42, height: 42)
            
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
                    DateTimeButton(datetime: notePreview.datetime,
                                   naturalDatetime: notePreview.naturalDatetime)
                }
                .foregroundStyle(.secondary)
                .font(.subheadline)
            }
        }
    }
}

@available(iOS 17, *)
#Preview(traits: .sizeThatFitsLayout) {
    NoteItemView(notePreview: OfflineFASession.default.notePreviews[0])
        .preferredColorScheme(.dark)
}
