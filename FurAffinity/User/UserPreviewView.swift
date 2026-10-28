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
        LoadingPlaceholder(cornerRadius: 0)
            .frame(height: bannerHeight)
    }
    
    var body: some View {
        List {
            Group {
                banner
                
                VStack(alignment: .leading, spacing: 0) {
                    UserHeader(
                        avatarUrl: preview.avatarUrl,
                        username: preview.username,
                        displayName: preview.displayName ?? " "
                    )
                    .padding(.vertical, 5)
                    .padding(.horizontal, 10)
                    
                    UserProfileControlView(username: preview.username)
                        .padding(.vertical, 5)
                    
                    // UserView's description HTMLView padding, plus its 8 text inset.
                    TextLinesPlaceholder(lineCount: 5)
                        .padding(.horizontal, 23)
                }
                .padding(.top, 5)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(.init())
        }
        .navigationTitle(preview.displayName ?? preview.username)
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
