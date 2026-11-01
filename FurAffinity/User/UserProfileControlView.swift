//
//  UserProfileControlView.swift
//  FurAffinity
//
//  Created by Ceylo on 04/09/2024.
//

import SwiftUI

struct UserProfileControlView: View {
    var username: String
    // Not private: skipstone can't bridge a private @State/@Environment.
    @Environment(\.navigationStream) var navigationStream
    
    var body: some View {
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
        #if !FA_SKIP_MODULE
        .scrollClipDisabled()
        #endif
    }
}

#Preview {
    UserProfileControlView(username: "foo")
}
