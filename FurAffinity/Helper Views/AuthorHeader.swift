//
//  AuthorHeader.swift
//  FurAffinity
//
//  Created by Ceylo on 03/08/2025.
//

import SwiftUI
import FAKit

struct AuthorHeader: View {
    var username: String
    var displayName: String
    var datetime: DatetimePair?
    
    var avatarUrl: URL? {
        FAURLs.avatarUrl(for: username)
    }
    
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
    
    var body: some View {
        HStack(alignment: .top) {
            FALink(destination: userFATarget) {
                AvatarView(avatarUrl: avatarUrl)
                    .frame(width: 42, height: 42)
            }
            
            HStack(alignment: .firstTextBaseline) {
                Text(displayName)
                    .font(.largeTitle)
                Spacer()
                
                if let datetime {
                    DateTimeButton(datetime: datetime.datetime,
                                   naturalDatetime: datetime.naturalDatetime)
                }
            }
        }
    }
}

#Preview {
    AuthorHeader(
        username: "ceylo",
        displayName: "Ceylo"
    )
    
    AuthorHeader(
        username: "ceylo",
        displayName: "Ceylo",
        datetime: .init("Apr 7th, 2022, 11:58 AM",
                        "8 months ago")
    )
}
