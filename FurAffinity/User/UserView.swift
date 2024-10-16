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
    
    private struct WatchControlStyle: LabelStyle {
        func makeBody(configuration: Configuration) -> some View {
            HStack(spacing: 5) {
                configuration.icon
                configuration.title
            }
            .font(.callout)
            .padding(5)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .stroke()
            }
            .foregroundStyle(Color.accentColor)
        }
    }
    
    @ViewBuilder
    var watchControl: some View {
        if let watchData = user.watchData {
            Spacer()
            Button {
                Task {
                    await toggleWatchAction()
                }
            } label: {
                Label(
                    watchData.watching ? "Unwatch" : "Watch",
                    systemImage: watchData.watching ? "bookmark.fill": "bookmark"
                )
                .labelStyle(WatchControlStyle())
            }
            // 🫠 https://forums.developer.apple.com/forums/thread/747558
            .buttonStyle(BorderlessButtonStyle())
            .sensoryFeedback(.impact, trigger: user.watchData?.watching, condition: {
                $1 == true
            })
        }
    }
    
    var body: some View {
        List {
            Group {
                banner
                
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        AvatarView(avatarUrl: FAURLs.avatarUrl(for: user.name))
                            .frame(width: 42, height: 42)
                        Text(user.displayName)
                            .font(.title)
                        watchControl
                    }
                    .padding(.vertical, 5)
                    
                    UserProfileControlView(username: user.name)
                        .padding(.horizontal, -15)
                        .padding(.vertical, 5)
                    
                    if let description = description.wrappedValue {
                        HTMLView(text: description, initialHeight: 300)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.top, 5)
                
                if !user.shouts.isEmpty {
                    Section {
                        CommentsView(comments: user.shouts)
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
    }
}

#Preview {
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
    //        .preferredColorScheme(.dark)
}
