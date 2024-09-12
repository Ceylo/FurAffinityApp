//
//  UserProfileControlView.swift
//  FurAffinity
//
//  Created by Ceylo on 04/09/2024.
//

import SwiftUI

struct UserProfileControlView: View {
    var username: String
    
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 0) {
                ForEach(UserProfileControl.allCases) { control in
                    Link(destination: control.destinationUrl(for: username)) {
                        Text(control.title)
                            .font(.headline)
                            .padding(15)
                    }
                }
            }
        }
        .background(.regularMaterial)
    }
}

#Preview {
    UserProfileControlView(username: "foo")
}
