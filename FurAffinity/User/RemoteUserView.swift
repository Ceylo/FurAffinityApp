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
    
    private func loadUser() async -> FAUser? {
        guard let session = model.session else { return nil }
        
        let user = await session.user(for: url)
        if let user {
            description = try? AttributedString(FAHTML: user.htmlDescription)
                .convertingLinksForInAppNavigation()
        }
        return user
    }
    
    var body: some View {
        PreviewableRemoteView(
            url: url,
            contentsLoader: loadUser,
            previewViewBuilder: {
                Group {
                    if let previewData {
                        UserPreviewView(preview: previewData)
                    } else if let username = FAURLs.usernameFrom(userUrl: url) {
                        UserPreviewView(preview: .init(username: username))
                    }
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
    }
}

#Preview {
    NavigationStack {
        RemoteUserView(url: FAURLs.userpageUrl(for: "terriniss")!)
    }
    .environmentObject(Model.demo)
//    .preferredColorScheme(.dark)
}
