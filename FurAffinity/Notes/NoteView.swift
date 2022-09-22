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
    @State private var activity: NSUserActivity?
    
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
        .toolbar {
            ToolbarItem {
                Link(destination: notePreview.noteUrl) {
                    Image(systemName: "safari")
                }
            }
        }
        .onAppear {
            if activity == nil {
                let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
                activity.title = notePreview.title
                activity.webpageURL = notePreview.noteUrl
                self.activity = activity
            }
            
            activity?.becomeCurrent()
        }
        .onDisappear {
            activity?.resignCurrent()
        }
    }
}

struct NoteView_Previews: PreviewProvider {
    static var previews: some View {
        NoteView(notePreview: OfflineFASession.default.notePreviews[1], noteProvider: { FANote.demo })
//            .preferredColorScheme(.dark)
            .environmentObject(Model.demo)
    }
}
