//
//  NoteView.swift
//  FurAffinity
//
//  Created by Ceylo on 11/04/2022.
//

import SwiftUI
import FAKit

struct NoteContentsView: View {
    var note: FANote
    var showWarning: Bool

    var userFATarget: FATarget? {
        guard let userUrl = try? FAURLs.userpageUrl(for: note.author) else {
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
    
    private var message: AttributedString {
        (showWarning ? note.message : note.messageWithoutWarning)
            .convertingLinksForInAppNavigation()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading) {
                HStack {
                    FALink(destination: userFATarget) {
                        HStack {
                            AvatarView(avatarUrl: FAURLs.avatarUrl(for: note.author))
                                .frame(width: 42, height: 42)
                            UserNameView(
                                name: note.author,
                                displayName: note.displayAuthor
                            )
                            .displayStyle(.multiline)
                            // Overwrite blue of FALink
                            .foregroundColor(.primary)
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
            
            HTMLView(text: message)
            // for text view inset
                .padding(.horizontal, -5)
        }
    }
}

struct NoteView: View {
    var note: FANote
    var replyAction: (_ destinationUser: String, _ subject: String, _ text: String) async throws -> Void

    @State private var replySession: NoteReplySession?
    
    var body: some View {
        ScrollView {
            NoteContentsView(note: note, showWarning: true)
            .padding()
            .navigationTitle(note.title)
            .navigationBarTitleDisplayMode(.inline)
            .noteReplySheet(on: $replySession) { reply in
                try await replyAction(reply.destinationUser, reply.subject, reply.text)
            }
        }
        .toolbar {
            RemoteContentToolbarItem(url: note.url) {
                Button {
                    replySession = .init(
                        defaultContents: .init(
                            destinationUser: note.author,
                            subject: note.title,
                            text: note.answerPlaceholderMessage
                        )
                    )
                } label: {
                    Label("Reply", systemImage: "message")
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        withAsync({ await FANote.demo }) { note in
            NoteView(
                note: note,
                replyAction: { destinationUser, subject, text in
                    print(destinationUser, subject, text)
                }
            )
        }
    }
//        .preferredColorScheme(.dark)
}
