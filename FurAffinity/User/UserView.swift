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
    var toggleWatchAction: () async -> Bool
    
    private let bannerHeight = 100.0
    
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
            if let url = FAURLs.userpageUrl(for: user.name) {
                RemoteContentToolbarItem(url: url) {
                    if let watchData = user.watchData {
                        WatchButton(watchData: watchData) {
                            _ = await toggleWatchAction()
                        }
                    }
                }
            }
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
                toggleWatchAction: { true }
            )
        }
    }
    //        .preferredColorScheme(.dark)
}
