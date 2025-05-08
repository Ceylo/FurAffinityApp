//
//  UserHeader.swift
//  FurAffinity
//
//  Created by Ceylo on 26/04/2025.
//

import SwiftUI

struct UserHeader: View {
    init(avatarUrl: URL? = nil, username: String, displayName: String) {
        self.avatarUrl = avatarUrl
        self.username = username
        self.displayName = displayName
    }
    
    var avatarUrl: URL?
    var username: String
    var displayName: String
    
    private var _label: AnyView?
    func label(@ViewBuilder _ view: () -> some View) -> Self {
        var copy = self
        copy._label = AnyView(view())
        return copy
    }
    
    private let avatarSize: CGFloat = 64
    var body: some View {
        HStack(alignment: .center) {
            AvatarView(avatarUrl: avatarUrl)
                .cornerRadius(12)
                .frame(width: avatarSize, height: avatarSize)
            UserNameView(
                name: username,
                displayName: displayName
            )
            .displayStyle(.multilineProminent)
            .label {
                if let _label {
                    _label
                }
            }
        }
    }
}

#Preview {
    UserHeader(
        username: "someuser",
        displayName: "Some User"
    )
    
    UserHeader(
        username: "someuser",
        displayName: "Some User"
    )
    .label {
        WatchingPill()
    }
}
