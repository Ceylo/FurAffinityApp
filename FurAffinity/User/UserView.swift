//
//  UserView.swift
//  FurAffinity
//
//  Created by Ceylo on 30/03/2023.
//

import SwiftUI
import FAKit
import Kingfisher

struct UserView: View {
    var user: FAUser
    var description: Binding<AttributedString?>
    var toggleWatchAction: () async throws -> Void
    var sendNoteAction: (_ destinationUser: String, _ subject: String, _ text: String) async throws -> Void
    
    private let bannerHeight = 100.0
    @State private var noteReplySession: NoteReplySession?
    
    var banner: some View {
        GeometryReader { geometry in
            FAImage(user.bannerUrl)
                .placeholder {
                    Rectangle()
                        .foregroundColor(.white.opacity(0.1))
                }
                .fade(duration: 0.25)
                .aspectRatio(contentMode: .fill)
                .frame(width: geometry.size.width,
                       height: bannerHeight,
                       alignment: .leading)
                .clipped()
        }
        .frame(height: bannerHeight)
    }
    
    @ToolbarContentBuilder
    var toolbar: some ToolbarContent {
        let url = try! FAURLs.userpageUrl(for: user.name)
        RemoteContentToolbarItem(url: url) {
            if let watchData = user.watchData {
                WatchButton(watchData: watchData) {
                    try? await toggleWatchAction()
                }
            }
            Button {
                noteReplySession = .init(defaultContents: .init(
                    destinationUser: user.name
                ))
            } label: {
                Label("Send a Note", systemImage: "bubble")
            }
        }
    }
    
    var body: some View {
        List {
            Group {
                banner
                VStack(alignment: .leading, spacing: 0) {
                    UserHeader(
                        avatarUrl: FAURLs.avatarUrl(for: user.name),
                        username: user.name,
                        displayName: user.displayName
                    )
                    .label {
                        if let watchData = user.watchData, watchData.watching {
                            WatchingPill()
                        }
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    
                    UserProfileControlView(username: user.name)
                        .padding(.vertical, 5)
                    
                    if let description = description.wrappedValue {
                        HTMLView(text: description, initialHeight: 300)
                            .padding(.horizontal, 15)
                    }
                }
                .padding(.top, 5)
                
                if !user.shouts.isEmpty {
                    Section {
                        CommentsView(
                            comments: user.shouts,
                            highlightedCommentId: user.targetShoutId
                        )
                    } header: {
                        SectionHeader(text: "Shouts")
                    }
                }
            }
            .listRowSeparator(.hidden)
            .listRowInsets(.init())
        }
        .navigationTitle(user.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.plain)
        .onAppear {
            prefetchAvatars(for: user.shouts)
        }
        .scrollToItem(id: user.targetShoutId)
        .toolbar {
            toolbar
        }
        .sensoryFeedback(.impact, trigger: user.watchData?.watching, condition: {
            $1 == true
        })
        .noteReplySheet(on: $noteReplySession) { reply in
            try await sendNoteAction(reply.destinationUser, reply.subject, reply.text)
        }
    }
}

#Preview {
    NavigationStack {
        withAsync({
            await (
                FAUser.demo,
                try! AttributedString(
                    FAHTML: FAUser.demo.htmlDescription
                ).convertingLinksForInAppNavigation()
            )
        }) { user, description in
            UserView(
                user: user,
                description: .constant(description),
                toggleWatchAction: { },
                sendNoteAction: { _, _, _ in }
            )
        }
    }
    //        .preferredColorScheme(.dark)
}
