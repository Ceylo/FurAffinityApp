//
//  SubmissionHeaderView.swift
//  FurAffinity
//
//  Created by Ceylo on 08/12/2021.
//

import SwiftUI
import FAKit
import URLImage

struct SubmissionHeaderView: View {
    var author: String
    var title: String
    var avatarUrl: URL?
    
    var avatar: some View {
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
    
    var body: some View {
        HStack {
            avatar
            
            VStack(alignment: .leading) {
                Text(author)
                    .font(.headline)
                
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct SubmissionHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        SubmissionHeaderView(author: "The Author", title: "Great Content", avatarUrl: nil)
            .previewLayout(.sizeThatFits)
            .preferredColorScheme(.dark)
            
    }
}
