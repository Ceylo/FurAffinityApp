//
//  AvatarView.swift
//  FurAffinity
//
//  Created by Ceylo on 09/04/2022.
//

import SwiftUI
import URLImage

struct AvatarView: View {
    var avatarUrl: URL?
    
    var body: some View {
        ZStack {
            if let avatarUrl = avatarUrl {
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
                .environment(\.urlImageOptions, URLImageOptions(loadOptions: [.loadImmediately, .loadOnAppear, .cancelOnDisappear]))
            } else {
                Rectangle()
                    .foregroundColor(.white.opacity(0.1))
            }
        }
        .cornerRadius(5)
        .frame(width: 32, height: 32)
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.borderOverlay.opacity(0.5), lineWidth: 1)
        }
            
    }
}

struct AvatarView_Previews: PreviewProvider {
    static var previews: some View {
        AvatarView(avatarUrl: URL(string: "https://a.furaffinity.net/20220409/furrycount.gif")!)
            .padding()
            .previewLayout(.sizeThatFits)
            .preferredColorScheme(.dark)
    }
}
