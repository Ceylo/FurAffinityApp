//
//  AvatarView.swift
//  FurAffinity
//
//  Created by Ceylo on 09/04/2022.
//

import SwiftUI
import FAKit
import Kingfisher

struct AvatarView: View {
    var avatarUrl: URL?
    
    @AppStorage(UserDefaultKeys.animateAvatars.rawValue)
    private var animateAvatars: Bool = true
    
    private func configure(_ image: some KFImageProtocol) -> some KFImageProtocol {
        image
            .placeholder {
                Rectangle()
                    .foregroundColor(.white.opacity(0.1))
            }
            .onFailureImage(.defaultAvatar)
            .fade(duration: 0.25)
    }
    
    var body: some View {
        ZStack {
            if animateAvatars {
                configure(FAAnimatedImage(avatarUrl))
            } else {
                configure(FAImage(avatarUrl))
            }
        }
        .cornerRadius(5)
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.borderOverlay, lineWidth: 1)
        }
    }
}

#Preview("With URL", traits: .sizeThatFitsLayout) {
    AvatarView(avatarUrl: URL(string: "https://a.furaffinity.net/terriniss.gif")!)
        .frame(width: 32, height: 32)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Empty", traits: .sizeThatFitsLayout) {
    AvatarView(avatarUrl: nil)
        .frame(width: 32, height: 32)
        .padding()
        .preferredColorScheme(.dark)
}
