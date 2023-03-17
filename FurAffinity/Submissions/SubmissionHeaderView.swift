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
    var datetime: String?
    
    var body: some View {
        HStack {
            AvatarView(avatarUrl: avatarUrl)
                .frame(width: 32, height: 32)
            
            VStack(alignment: .leading) {
                HStack(alignment: .firstTextBaseline) {
                    Text(author)
                        .font(.headline)
                    Spacer()
                    if let datetime {
                        Text(datetime)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct SubmissionHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        SubmissionHeaderView(author: "The Author", title: "Great Content", avatarUrl: nil, datetime: "1h ago")
            .previewLayout(.sizeThatFits)
            .preferredColorScheme(.dark)
            
    }
}
