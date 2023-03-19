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
    var username: String
    var displayName: String
    var title: String
    var avatarUrl: URL?
    
    struct FullDatetime {
        var datetime: String
        var naturalDatetime: String
        
        init(_ datetime: String, _ naturalDatetime: String) {
            self.datetime = datetime
            self.naturalDatetime = naturalDatetime
        }
    }
    var datetime: FullDatetime?
    
    var body: some View {
        HStack {
            OptionalLink(destination: inAppUserUrl(for: username)) {
                AvatarView(avatarUrl: avatarUrl)
                    .frame(width: 32, height: 32)
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

struct SubmissionHeaderView_Previews: PreviewProvider {
    static var previews: some View {
        SubmissionHeaderView(username: "author",
                             displayName: "The Author", title: "Great Content",
                             avatarUrl: nil,
                             datetime: .init("Apr 7th, 2022, 11:58 AM",
                                             "8 months ago"))
        .previewLayout(.sizeThatFits)
            .preferredColorScheme(.dark)
            
    }
}
