//
//  UserView.swift
//  FurAffinity
//
//  Created by Ceylo on 30/03/2023.
//

import SwiftUI
import FAKit
import URLImage

private enum Control: Int, CaseIterable, Identifiable {
    var id: Int { rawValue }

    case gallery
    case scraps
    case favorites
}

extension Control {
    var title: String {
        switch self {
        case .gallery: return "Gallery"
        case .scraps: return "Scraps"
        case .favorites: return "Favs"
        }
    }
    
    func destinationUrl(for user: String) -> URL {
        switch self {
        case .gallery:
            return FAURLs.galleryUrl(for: user)
                .convertedForInAppNavigation
        case .scraps:
            return FAURLs.scrapsUrl(for: user)
                .convertedForInAppNavigation
        case .favorites:
            return FAURLs.favoritesUrl(for: user)
                .convertedForInAppNavigation
        }
    }
}

struct UserView: View {
    var user: FAUser
    var description: Binding<AttributedString?>
    var toggleWatchAction: () -> Void
    
    private let bannerHeight = 100.0
    
    var banner: some View {
        GeometryReader { geometry in
            URLImage(user.bannerUrl) { progress in
                Rectangle()
                    .foregroundColor(.white.opacity(0.1))
            } failure: { error, retry in
                Image(systemName: "questionmark")
                    .resizable()
            } content: { image, info in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geometry.size.width,
                           height: bannerHeight,
                           alignment: .leading)
                    .clipped()
                    .transition(.opacity.animation(.default.speed(2)))
            }
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
    
    var watchControl: some View {
        Group {
            if let watchData = user.watchData {
                Spacer()
                Button(action: toggleWatchAction) {
                    Label(
                        watchData.watching ? "Unwatch" : "Watch",
                        systemImage: watchData.watching ? "bookmark.fill": "bookmark"
                    )
                    .labelStyle(WatchControlStyle())
                }
                // 🫠 https://forums.developer.apple.com/forums/thread/747558
                .buttonStyle(BorderlessButtonStyle())
            }
        }
    }
    
    var controls: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(Control.allCases) { control in
                    Link(destination: control.destinationUrl(for: user.name)) {
                        Text(control.title)
                            .font(.headline)
                            .padding(10)
                    }
                }
            }
        }
        .background(.regularMaterial)
    }
    
    var body: some View {
        List {
            Group {
                banner
                
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        AvatarView(avatarUrl: user.avatarUrl)
                            .frame(width: 32, height: 32)
                        Text(user.displayName)
                            .font(.title)
                        watchControl
                    }
                    
                    controls
                        .padding(.horizontal, -15)
                        .padding(.vertical, 5)
                    
                    if let description = description.wrappedValue {
                        HTMLView(text: description, initialHeight: 300)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.top, 5)
                
                Section {
                    CommentsView(comments: user.shouts)
                } header: {
                    SectionHeader(text: "Shouts")
                }
            }
            .listRowSeparator(.hidden)
            .listRowInsets(.init())
        }
        .navigationTitle(user.displayName)
        .listStyle(.plain)
    }
}

struct UserView_Previews: PreviewProvider {
    static var previews: some View {
        let description = AttributedString(
            FAHTML: FAUser.demo.htmlDescription
        )?.convertingLinksForInAppNavigation()
        UserView(
            user: FAUser.demo,
            description: .constant(description),
            toggleWatchAction: {}
        )
        //        .preferredColorScheme(.dark)
    }
}
