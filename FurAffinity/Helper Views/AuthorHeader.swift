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
    
    init(username: String, displayName: String, datetime: DatetimePair? = nil, _displayStaticName: Bool = false) {
        self.username = username
        self.displayName = displayName
        self.datetime = datetime
    }
    
    var avatarUrl: URL? {
        FAURLs.avatarUrl(for: username)
    }
    
    private var _displayStaticName = false
    func displayingStaticName(_ display: Bool = true) -> Self {
        var copy = self
        copy._displayStaticName = display
        return copy
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
            
            HStack(alignment: .lastTextBaseline) {
                FALink(destination: userFATarget) {
                    UserNameView(
                        name: username,
                        displayName: displayName
                    )
                    .displayStyle(_displayStaticName ? .multiline : .prominent)
                    Spacer()
                }
                
                if let datetime {
                    DateTimeButton(datetime: datetime.datetime,
                                   naturalDatetime: datetime.naturalDatetime)
                }
            }
            // Overwrite blue of FALink
            .foregroundColor(.primary)
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
    
    AuthorHeader(
        username: "ceylo",
        displayName: "Ceylo",
        datetime: .init("Apr 7th, 2022, 11:58 AM",
                        "8 months ago")
    )
    .displayingStaticName()
}
