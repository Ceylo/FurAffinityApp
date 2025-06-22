//
//  AvatarView.swift
//  FurAffinity
//
//  Created by Ceylo on 09/04/2022.
//

import SwiftUI
import FAKit
import Kingfisher
import Defaults

struct AvatarView: View {
    var avatarUrl: URL?
    @Default(.animateAvatars) var animateAvatars
    private var cornerRadius: CGFloat = 5
    private var fadeDuration = 0.25
    
    init(avatarUrl: URL? = nil) {
        self.avatarUrl = avatarUrl
    }
    
    func cornerRadius(_ radius: CGFloat) -> Self {
        var copy = self
        copy.cornerRadius = radius
        return copy
    }
    
    func fadeDuration(_ duration: Double) -> Self {
        var copy = self
        copy.fadeDuration = duration
        return copy
    }
    
    private func configure(_ image: some KFImageProtocol) -> some KFImageProtocol {
        image
            .placeholder {
                Rectangle()
                    .foregroundColor(.white.opacity(0.1))
            }
            .onFailureImage(.defaultAvatar)
            .fade(duration: fadeDuration)
    }
    
    var body: some View {
        ZStack {
            if animateAvatars {
                configure(FAAnimatedImage(avatarUrl))
            } else {
                configure(FAImage(avatarUrl))
            }
        }
        .cornerRadius(cornerRadius)
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
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
