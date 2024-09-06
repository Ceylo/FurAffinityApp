//
//  RemoteUserView.swift
//  FurAffinity
//
//  Created by Ceylo on 19/03/2023.
//

import SwiftUI
import FAKit
import URLImage

struct RemoteUserView: View {
    var url: URL
    var previewData: UserPreviewData?
    @EnvironmentObject var model: Model
    @State private var description: AttributedString?
    @Environment(\.avatarProvider) var avatarProvider
    @State private var avatarUrl: URL?
    
    private func loadUser() async -> FAUser? {
        guard let session = model.session else { return nil }
        
        let user = await session.user(for: url)
        if let user {
            description = try? AttributedString(FAHTML: user.htmlDescription)
                .convertingLinksForInAppNavigation()
        }
        return user
    }
    
    private var username: String? {
        previewData?.username ?? FAURLs.usernameFrom(userUrl: url)
    }
    
    private var augmentedPreviewData: UserPreviewData? {
        if let previewData {
            UserPreviewData(
                username: previewData.username,
                displayName: previewData.displayName,
                avatarUrl: previewData.avatarUrl ?? avatarUrl
            )
        } else if let username {
            UserPreviewData(
                username: username,
                displayName: previewData?.displayName,
                avatarUrl: previewData?.avatarUrl ?? avatarUrl
            )
        } else {
            nil
        }
    }
    
    var body: some View {
        PreviewableRemoteView(
            url: url,
            contentsLoader: loadUser,
            previewViewBuilder: {
                if let augmentedPreviewData {
                    UserPreviewView(preview: augmentedPreviewData)
                }
            },
            contentsViewBuilder: { user, updateHandler in
                UserView(
                    user: user,
                    description: $description,
                    toggleWatchAction: {
                        Task {
                            let updatedUser = await model.session?.toggleWatch(for: user)
                            updateHandler.update(with: updatedUser)
                        }
                    }
                )
            }
        )
        .task {
            guard previewData?.avatarUrl == nil else {
                return
            }
            
            if let username {
                avatarUrl = await avatarProvider?.avatarUrl(for: username)
            } else {
                logger.warning("Could not parse username from url: \(url, privacy: .public)")
            }
        }
    }
}

#Preview {
    NavigationStack {
        RemoteUserView(url: FAURLs.userpageUrl(for: "terriniss")!)
    }
    .environmentObject(Model.demo)
//    .preferredColorScheme(.dark)
}
