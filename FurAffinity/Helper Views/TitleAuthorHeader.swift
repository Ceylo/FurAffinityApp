//
//  HeaderView.swift
//  FurAffinity
//
//  Created by Ceylo on 08/12/2021.
//

import SwiftUI
import FAKit

struct TitleAuthorHeader: View {
    var username: String
    var displayName: String
    var title: String
    var datetime: DatetimePair?
    
    var userFATarget: FATarget? {
        guard let userUrl = try? FAURLs.userpageUrl(for: username) else {
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
    
    var avatarUrl: URL? {
        FAURLs.avatarUrl(for: username)
    }
    
    var primaryText: String {
        title
    }
    
    var secondaryText: String {
        "by " + displayName
    }
    
    var body: some View {
        HStack(alignment: .top) {
            FALink(destination: userFATarget) {
                AvatarView(avatarUrl: avatarUrl)
                    .frame(width: 42, height: 42)
            }
            
            VStack(alignment: .leading) {
                Text(primaryText)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                HStack(alignment: .lastTextBaseline) {
                    Text(secondaryText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    if let datetime {
                        DateTimeButton(datetime: datetime.datetime,
                                       naturalDatetime: datetime.naturalDatetime)
                    }
                }
            }
        }
    }
}

extension TitleAuthorHeader: SubmissionHeaderView {
    init(preview: FASubmissionPreview) {
        self.init(
            username: preview.author,
            displayName: preview.displayAuthor,
            title: preview.title
        )
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    withAsync({ try await Model.empty }) {
        NavigationStack {
            List {
                TitleAuthorHeader(
                    username: "author",
                    displayName: "The Author", title: "Great Content but with very very very very long description",
                    datetime: .init("Apr 7th, 2022, 11:58 AM",
                                    "8 months ago")
                )
            }
            .listStyle(.plain)
        }
        .preferredColorScheme(.dark)
        .environment($0)
    }
}
