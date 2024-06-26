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
    @State private var activity: NSUserActivity?
    
    func loadNote(forceReload: Bool) async {
        guard note == nil || forceReload else {
            return
        }
        
        note = await model.session?.note(for: url)
        if let note {
            avatarUrl = await model.session?.avatarUrl(for: note.author)
        }
    }
    
    var body: some View {
        ScrollView {
            if let note {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading) {
                        HStack {
                            OptionalLink(destination: inAppUserUrl(for: note.author)) {
                                AvatarView(avatarUrl: avatarUrl)
                                    .frame(width: 42, height: 42)
                                
                                Text(note.displayAuthor)
                                    .foregroundColor(.primary)
                            }
                            Spacer()
                            DateTimeButton(datetime: note.datetime,
                                           naturalDatetime: note.naturalDatetime)
                        }
                        
                        Text(note.title)
                            .font(.title2)
                    }
                    Divider()
                        .padding(.vertical, 5)
                    
                    HTMLView(text: note.message.convertingLinksForInAppNavigation())
                    // for text view inset
                        .padding(.horizontal, -5)
                }
                .padding()
                .navigationTitle(note.title)
            }
        }
        .task {
            await loadNote(forceReload: false)
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
