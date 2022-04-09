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
    
    var body: some View {
        HStack {
            AvatarView(avatarUrl: avatarUrl)
            
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
