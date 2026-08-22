//
//  UserProfileControlView.swift
//  FurAffinity
//
//  Created by Ceylo on 04/09/2024.
//

import SwiftUI

struct UserProfileControlView: View {
    var username: String
    // Non-private: skipstone can't bridge a private state property.
    @Environment(\.navigationStream) var navigationStream
    
    var body: some View {
        if #available(iOS 26, *) {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(UserProfileControl.allCases) { control in
                        // Not FALink: it applies .buttonStyle(.borderless) in its
                        // own body, which would override the .glass style below.
                        Button {
                            navigationStream.send(control.target(for: username))
                        } label: {
                            Text(control.title)
                                .font(.headline)
                                .padding(5)
                        }
                        .buttonStyle(.glass)
                    }
                }
                .padding(5)
            }
            .scrollClipDisabled()
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(UserProfileControl.allCases) { control in
                        Button {
                            navigationStream.send(control.target(for: username))
                        } label: {
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
