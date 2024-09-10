//
//  UserPreviewView.swift
//  FurAffinity
//
//  Created by Ceylo on 30/03/2023.
//

import SwiftUI
import FAKit
import URLImage

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
                            .frame(width: 42, height: 42)
                        if let displayName = preview.displayName {
                            Text(displayName)
                                .font(.title)
                        }
                    }
                    .padding(.vertical, 5)
                    
                    UserProfileControlView(username: preview.username)
                        .padding(.horizontal, -15)
                        .padding(.vertical, 5)
                }
                .padding(.horizontal, 15)
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
                    avatarUrl: user.avatarUrl
                )
            )
        }
    }
}
