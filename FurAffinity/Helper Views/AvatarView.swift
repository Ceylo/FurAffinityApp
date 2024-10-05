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
    
    var body: some View {
        ZStack {
            FAImage(avatarUrl)
                .placeholder {
                    Rectangle()
                        .foregroundColor(.white.opacity(0.1))
                }
                .onFailureImage(.defaultAvatar)
                .resizable()
                .fade(duration: 0.25)
        }
        .cornerRadius(5)
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.borderOverlay, lineWidth: 1)
        }
    }
}

@available(iOS 17, *)
#Preview("With URL", traits: .sizeThatFitsLayout) {
    AvatarView(avatarUrl: URL(string: "https://a.furaffinity.net/terriniss.gif")!)
        .frame(width: 32, height: 32)
        .padding()
        .preferredColorScheme(.dark)
}

@available(iOS 17, *)
#Preview("Empty", traits: .sizeThatFitsLayout) {
    AvatarView(avatarUrl: nil)
        .frame(width: 32, height: 32)
        .padding()
        .preferredColorScheme(.dark)
}
