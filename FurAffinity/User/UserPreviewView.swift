//
//  UserPreviewView.swift
//  FurAffinity
//
//  Created by Ceylo on 30/03/2023.
//

import SwiftUI
import FAKit

struct UserPreviewData: Hashable {
    var username: String
    var displayName: String?
    var avatarUrl: URL?
}

struct UserPreviewView: View {
    var preview: UserPreviewData
    
    private let bannerHeight = 100.0
    
    var banner: some View {
        Rectangle()
            .foregroundStyle(.clear)
            .frame(height: bannerHeight)
    }
    
    var body: some View {
        List {
            Group {
                banner
                
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        AvatarView(avatarUrl: preview.avatarUrl)
                            .cornerRadius(12)
                            .frame(width: 64, height: 64)
                        if let displayName = preview.displayName {
                            UserNameView(
                                name: preview.username,
                                displayName: displayName
                            )
                            .displayStyle(.multilineProminent)
                        }
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    
                    UserProfileControlView(username: preview.username)
                        .padding(.vertical, 5)
                }
                .padding(.top, 5)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(.init())
        }
        .navigationTitle(preview.displayName ?? preview.username)
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.plain)
    }
}

#Preview("Minimal contents") {
    NavigationStack {
        UserPreviewView(
            preview: .init(username: "foo")
        )
    }
}

#Preview("Full preview") {
    withAsync({ await FAUser.demo }) { user in
        NavigationStack {
            UserPreviewView(
                preview: .init(
                    username: "foo",
                    displayName: "Foo",
                    avatarUrl: FAURLs.avatarUrl(for: "foo")
                )
            )
        }
    }
}
