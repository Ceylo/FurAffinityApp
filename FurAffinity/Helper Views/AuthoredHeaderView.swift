//
//  HeaderView.swift
//  FurAffinity
//
//  Created by Ceylo on 08/12/2021.
//

import SwiftUI
import FAKit
import URLImage

struct AuthoredHeaderView: View {
    var username: String
    var displayName: String
    var title: String
    var avatarUrl: URL?
    var datetime: DatetimePair?
    
    var body: some View {
        HStack(alignment: .top) {
            OptionalLink(destination: inAppUserUrl(for: username)) {
                AvatarView(avatarUrl: avatarUrl)
                    .frame(width: 38, height: 38)
            }
            
            VStack(alignment: .leading) {
                HStack(alignment: .firstTextBaseline) {
                    OptionalLink(destination: inAppUserUrl(for: username)) {
                        Text(displayName)
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    if let datetime {
                        DateTimeButton(datetime: datetime.datetime,
                                       naturalDatetime: datetime.naturalDatetime)
                    }
                }
                
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }
}

extension AuthoredHeaderView: SubmissionHeaderView {
    init(preview: FASubmissionPreview, avatarUrl: URL?) {
        self.init(
            username: preview.author,
            displayName: preview.displayAuthor,
            title: preview.title,
            avatarUrl: avatarUrl
        )
    }
}

struct SubmissionAuthoredHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        AuthoredHeaderView(
            username: "author",
            displayName: "The Author", title: "Great Content but with very very very very long description",
            avatarUrl: nil,
            datetime: .init("Apr 7th, 2022, 11:58 AM",
                            "8 months ago")
        )
        .previewLayout(.sizeThatFits)
        .preferredColorScheme(.dark)
        
    }
}
