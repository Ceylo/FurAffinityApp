//
//  NoteView.swift
//  FurAffinity
//
//  Created by Ceylo on 11/04/2022.
//

import SwiftUI
import FAKit

struct NoteView: View {
    var url: URL
    @EnvironmentObject var model: Model
    
    @State private var note: FANote?
    @State private var avatarUrl: URL?
    @State private var message: AttributedString?
    @State private var showExactDatetime = false
    @State private var activity: NSUserActivity?
    
    func loadNote() async {
        note = await model.session?.note(for: url)
        if let note {
            avatarUrl = await model.session?.avatarUrl(for: note.author)
            message = AttributedString(FAHTML: note.htmlMessage)?
                .convertingLinksForInAppNavigation()
        }
    }
    
    var body: some View {
        ScrollView {
            if let note {
                VStack(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            AvatarView(avatarUrl: avatarUrl)
                                .frame(width: 42, height: 42)
                            
                            Text(note.displayAuthor)
                            Spacer()
                            Button(showExactDatetime ? note.datetime : note.naturalDatetime) {
                                showExactDatetime.toggle()
                            }
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                        }
                        
                        Text(note.title)
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
                .navigationTitle(note.title)
            }
        }
        .task {
            await loadNote()
        }
        .toolbar {
            ToolbarItem {
                Link(destination: url) {
                    Image(systemName: "safari")
                }
            }
        }
        .onAppear {
            if activity == nil {
                let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
                activity.webpageURL = url
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
        NoteView(url: OfflineFASession.default.notePreviews[1].noteUrl)
//            .preferredColorScheme(.dark)
            .environmentObject(Model.demo)
    }
}
