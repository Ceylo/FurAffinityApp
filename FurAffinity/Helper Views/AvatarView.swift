//
//  AvatarView.swift
//  FurAffinity
//
//  Created by Ceylo on 09/04/2022.
//

import SwiftUI
import URLImage
import FAKit

struct AvatarView: View {
    var avatarUrl: URL?
    
    var body: some View {
        ZStack {
            if let avatarUrl {
                URLImage(avatarUrl) { progress in
                    Rectangle()
                        .foregroundColor(.white.opacity(0.1))
                } failure: { error, retry in
                    Image(systemName: "questionmark")
                        .resizable()
                } content: { image, info in
                    image
                        .resizable()
                        .transition(.opacity.animation(.default.speed(2)))
                }
            } else {
                Rectangle()
                    .foregroundColor(.white.opacity(0.1))
            }
        }
        .cornerRadius(5)
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.borderOverlay.opacity(0.5), lineWidth: 1)
        }
            
    }
}

@available(iOS 17, *)
#Preview(traits: .sizeThatFitsLayout) {
    AvatarView(avatarUrl: URL(string: "https://a.furaffinity.net/20220409/furrycount.gif")!)
        .frame(width: 32, height: 32)
        .padding()
        .preferredColorScheme(.dark)
}
