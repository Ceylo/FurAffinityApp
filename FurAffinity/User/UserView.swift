//
//  UserView.swift
//  FurAffinity
//
//  Created by Ceylo on 30/03/2023.
//

import SwiftUI
import FAKit
import URLImage

struct UserView: View {
    var user: FAUser
    var description: AttributedString?
    
    private let bannerHeight = 100.0
    
    var body: some View {
        VStack(alignment: .leading) {
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
            
            VStack(alignment: .leading) {
                HStack {
                    AvatarView(avatarUrl: user.avatarUrl)
                        .frame(width: 32, height: 32)
                    Text(user.displayName)
                        .font(.title)
                }
                
                if let description {
                    TextView(text: description, initialHeight: 300)
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle(user.displayName)
        .navigationBarTitleDisplayMode(.inline)
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
