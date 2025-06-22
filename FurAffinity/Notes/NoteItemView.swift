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
    
    private var target: FATarget? {
        guard let url = try? FAURLs.userpageUrl(for: notePreview.author) else {
            return nil
        }
        
        return .user(
            url: url,
            previewData: .init(
                username: notePreview.author,
                displayName: notePreview.displayAuthor,
                avatarUrl: FAURLs.avatarUrl(for: notePreview.author)
            )
        )
    }
    
    var body: some View {
        HStack(alignment: .top) {
            FALink(destination: target) {
                AvatarView(avatarUrl: FAURLs.avatarUrl(for: notePreview.author))
                    .frame(width: 42, height: 42)
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
                    UserNameView(
                        name: notePreview.author,
                        displayName: notePreview.displayAuthor
                    )
                    Spacer()
                    DateTimeButton(datetime: notePreview.datetime,
                                   naturalDatetime: notePreview.naturalDatetime)
                }
            }
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    NoteItemView(notePreview: OfflineFASession.default.notePreviews[0])
        .preferredColorScheme(.dark)
}
