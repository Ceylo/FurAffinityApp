//
//  RemoteUserView.swift
//  FurAffinity
//
//  Created by Ceylo on 19/03/2023.
//

import SwiftUI
import FAKit

struct RemoteUserView: View {
    var url: URL
    var previewData: UserPreviewData?
    @Environment(Model.self) private var model
    @Environment(ErrorStorage.self) private var errorStorage
    @State private var description: AttributedString?
    
    private func loadUser(from url: URL) async throws -> FAUser {
        let session = try model.session.unwrap()
        let user = try await session.user(for: url)
        description = try await AttributedString(FAHTML: user.htmlDescription)
            .convertingLinksForInAppNavigation()
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
                avatarUrl: previewData.avatarUrl ?? FAURLs.avatarUrl(for: previewData.username)
            )
        } else if let username {
            UserPreviewData(
                username: username,
                displayName: previewData?.displayName,
                avatarUrl: previewData?.avatarUrl ?? FAURLs.avatarUrl(for: username)
            )
        } else {
            nil
        }
    }
    
    var body: some View {
        PreviewableRemoteView(
            url: url,
            dataSource: loadUser,
            preview: {
                if let augmentedPreviewData {
                    UserPreviewView(preview: augmentedPreviewData)
                }
            },
            view: { user, updateHandler in
                UserView(
                    user: user,
                    description: $description,
                    toggleWatchAction: {
                        await storeLocalizedError(in: errorStorage, action: "Toggle Watch", webBrowserURL: nil) {
                            let updatedUser = try await model.session.unwrap().toggleWatch(for: user)
                            updateHandler.update(with: updatedUser)
                        }
                    },
                    sendNoteAction: { destinationUser, subject, text in
                        let session = try model.session.unwrap()
                        try await session.sendNote(
                            toUsername: destinationUser,
                            subject: subject,
                            message: text
                        )
                    }
                )
            }
        )
    }
}

#Preview {
    withAsync({ try await Model.demo }) {
        NavigationStack {
            RemoteUserView(url: try! FAURLs.userpageUrl(for: "terriniss"))
        }
        .environment($0)
        .environment($0.errorStorage)
        //    .preferredColorScheme(.dark)
    }
}
