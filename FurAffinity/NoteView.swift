//
//  NoteView.swift
//  FurAffinity
//
//  Created by Ceylo on 11/04/2022.
//

import SwiftUI
import FAKit

struct NoteView: View {
    var notePreview: FANotePreview
    var noteProvider: () async -> FANote?
    @EnvironmentObject var model: Model
    
    @State private var avatarUrl: URL?
    @State private var message: AttributedString?
    @State private var showExactDatetime = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading) {
                VStack(alignment: .leading, spacing: 20) {
                    HStack {
                        AvatarView(avatarUrl: avatarUrl)
                            .task {
                                avatarUrl = await model.session?.avatarUrl(for: notePreview.author)
                            }
                            .frame(width: 42, height: 42)
                        
                        Text(notePreview.displayAuthor)
                        Spacer()
                        Button(showExactDatetime ? notePreview.datetime : notePreview.naturalDatetime) {
                            showExactDatetime.toggle()
                        }
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                    }
                    
                    Text(notePreview.title)
                        .font(.title2)
                }
                Divider()
                
                if let message = message {
                    TextView(text: message)
                    // for text view inset
                        .padding(.horizontal, -5)
                }
            }
            .padding()
        }
        .task {
            if let note = await noteProvider() {
                self.message = AttributedString(FAHTML: note.htmlMessage)
            }
        }
    }
}

struct NoteView_Previews: PreviewProvider {
    static var previews: some View {
        NoteView(notePreview: OfflineFASession.default.notePreviews[0], noteProvider: { FANote.demo })
//            .preferredColorScheme(.dark)
            .environmentObject(Model.demo)
    }
}
