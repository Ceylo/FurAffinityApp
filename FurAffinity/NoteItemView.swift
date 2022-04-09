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
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                if notePreview.unread {
                    Circle()
                        .frame(width: 10, height: 10)
                        .foregroundColor(.accentColor)
                }
                
                Text(notePreview.title)
            }
            
            HStack {
                Text("From " + notePreview.displayAuthor)
                Spacer()
                Text(notePreview.datetime)
            }
            .foregroundStyle(.secondary)
            .font(.footnote)
        }
    }
}

struct NoteItemView_Previews: PreviewProvider {
    static var previews: some View {
        NoteItemView(notePreview: OfflineFASession.default.notePreviews[0])
            .previewLayout(.sizeThatFits)
            .preferredColorScheme(.dark)
    }
}
