//
//  RemoteSubmissionView.swift
//  FurAffinity
//
//  Created by Ceylo on 21/11/2021.
//

import SwiftUI
import FAKit

struct RemoteSubmissionView: View {
    @EnvironmentObject var model: Model
    
    var url: URL
    var previewData: FASubmissionPreview?
    @Environment(\.avatarProvider) var avatarProvider
    @State private var previewAvatarUrl: URL?
    @State private var activity: NSUserActivity?
    
    private func loadSubmission() async -> (submission: FASubmission, avatarURL: URL?)? {
        guard let submission = await model.session?.submission(for: url) else {
            return nil
        }
        
        let avatarUrl = await model.session?.avatarUrl(for: submission.author)
        return (submission, avatarUrl)
    }
    
    private var username: String? {
        previewData?.author ?? FAURLs.usernameFrom(userUrl: url)
    }
    
    var body: some View {
        PreviewableRemoteView(
            url: url,
            contentsLoader: loadSubmission,
            previewViewBuilder: {
                if let previewData {
                    return SubmissionPreviewView(submission: previewData, avatarUrl: previewAvatarUrl)
                } else {
                    return nil
                }
            },
            contentsViewBuilder: { contents, updateHandler in
                SubmissionView(
                    submission: contents.submission,
                    avatarUrl: contents.avatarURL,
                    thumbnail: previewData?.dynamicThumbnail,
                    favoriteAction: {
                        Task {
                            let updated = try await model.toggleFavorite(for: contents.submission)
                            updateHandler.update(with: updated.map { ($0, contents.avatarURL) })
                        }
                    },
                    replyAction: { parentCid, text in
                        Task {
                            let updated = try await model.postComment(
                                on: contents.submission,
                                replytoCid: parentCid,
                                contents: text
                            )
                            updateHandler.update(with: updated.map { ($0, contents.avatarURL) })
                        }
                    })
            }
        )
        .task {
            if previewAvatarUrl == nil, let username {
                previewAvatarUrl = await avatarProvider?.avatarUrl(for: username)
            }
        }
        .onAppear {
            if activity == nil {
                let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
                activity.webpageURL = url
                self.activity = activity
            }
            
            activity?.becomeCurrent()
        }
        .onDisappear {
            activity?.resignCurrent()
        }
    }
}

#Preview {
    RemoteSubmissionView(
        url: FASubmissionPreview.demo.url,
        previewData: .demo
    )
//    .preferredColorScheme(.dark)
    .environmentObject(Model.demo)
}
