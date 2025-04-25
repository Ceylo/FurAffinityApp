//
//  NoteView.swift
//  FurAffinity
//
//  Created by Ceylo on 11/04/2022.
//

import SwiftUI
import FAKit

struct NoteView: View {
    var note: FANote
    
    var userFATarget: FATarget? {
        guard let userUrl = FAURLs.userpageUrl(for: note.author) else {
            return nil
        }
        
        return .user(
            url: userUrl,
            previewData: .init(
                username: note.author,
                displayName: note.displayAuthor,
                avatarUrl: FAURLs.avatarUrl(for: note.author)
            )
        )
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading) {
                    HStack {
                        FALink(destination: userFATarget) {
                            HStack {
                                AvatarView(avatarUrl: FAURLs.avatarUrl(for: note.author))
                                    .frame(width: 42, height: 42)
                                
                                VStack(alignment: .leading) {
                                    Text(note.displayAuthor)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text("@\(note.author)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
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
            .navigationBarTitleDisplayMode(.inline)
        }
        .toolbar {
            RemoteContentToolbarItem(url: note.url)
        }
    }
}
