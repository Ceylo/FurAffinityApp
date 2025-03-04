//
//  HeaderView.swift
//  FurAffinity
//
//  Created by Ceylo on 08/12/2021.
//

import SwiftUI
import FAKit

struct AuthoredHeaderView: View {
    var username: String
    var displayName: String
    var title: String
    var avatarUrl: URL?
    var datetime: DatetimePair?
    
    var userFATarget: FATarget? {
        guard let userUrl = FAURLs.userpageUrl(for: username) else {
            return nil
        }
        
        return .user(
            url: userUrl,
            previewData: .init(
                username: username,
                displayName: displayName,
                avatarUrl: avatarUrl
            )
        )
    }
    
    var body: some View {
        HStack(alignment: .top) {
            FALink(destination: userFATarget) {
                AvatarView(avatarUrl: avatarUrl)
                    .frame(width: 38, height: 38)
            }
            
            VStack(alignment: .leading) {
                HStack(alignment: .firstTextBaseline) {
                    Text(displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
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

#Preview(traits: .sizeThatFitsLayout) {
    NavigationStack {
        List {
            AuthoredHeaderView(
                username: "author",
                displayName: "The Author", title: "Great Content but with very very very very long description",
                avatarUrl: nil,
                datetime: .init("Apr 7th, 2022, 11:58 AM",
                                "8 months ago")
            )
        }
        .listStyle(.plain)
    }
    .preferredColorScheme(.dark)
    .environmentObject(Model.empty)
}
