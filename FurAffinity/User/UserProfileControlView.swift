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
        if #available(iOS 26, *) {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(UserProfileControl.allCases) { control in
                        Link(destination: control.destinationUrl(for: username)) {
                            Text(control.title)
                                .font(.headline)
                                .padding(5)
                        }
                        .buttonStyle(.glass)
                    }
                }
                .padding(5)
            }
        } else {
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
}

#Preview {
    UserProfileControlView(username: "foo")
}
