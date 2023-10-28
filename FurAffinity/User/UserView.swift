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
    var description: AttributedString?
    
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
        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
            banner
            
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    AvatarView(avatarUrl: user.avatarUrl)
                        .frame(width: 32, height: 32)
                    Text(user.displayName)
                        .font(.title)
                }
                
                controls
                    .padding(.horizontal, -15)
                    .padding(.vertical, 5)
                
                if let description {
                    TextView(text: description, initialHeight: 300)
                }
            }
            .padding(.horizontal, 15)
            .padding(.top, 5)
            
            Section {
                CommentsView(comments: user.shouts)
                    .padding()
            } header: {
                HStack {
                    Text("Shouts")
                        .font(.callout)
                    Spacer()
                }
                .padding(10)
                .background(.regularMaterial)
            }
        }
        .navigationTitle(user.displayName)
    }
}

struct UserView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            let description = AttributedString(
                FAHTML: FAUser.demo.htmlDescription
            )?.convertingLinksForInAppNavigation()
            UserView(user: FAUser.demo,
                     description: description)
        }
    }
}
