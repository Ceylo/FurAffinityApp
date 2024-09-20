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
    @State private var activity: NSUserActivity?
    
    private var username: String? {
        previewData?.author ?? FAURLs.usernameFrom(userUrl: url)
    }
    
    var body: some View {
        PreviewableRemoteView(
            url: url,
            contentsLoader: {
                await model.session?.submission(for: url)
            },
            previewViewBuilder: {
                previewData.map {
                    SubmissionPreviewView(
                        submission: $0,
                        avatarUrl: FAURLs.avatarUrl(for: $0.author)
                    )
                }
            },
            contentsViewBuilder: { submission, updateHandler in
                SubmissionView(
                    submission: submission,
                    avatarUrl: FAURLs.avatarUrl(for: submission.author),
                    thumbnail: previewData?.dynamicThumbnail,
                    favoriteAction: {
                        Task {
                            let updated = try await model.toggleFavorite(for: submission)
                            updateHandler.update(with: updated)
                        }
                    },
                    replyAction: { parentCid, text in
                        Task {
                            let updated = try await model.postComment(
                                on: submission,
                                replytoCid: parentCid,
                                contents: text
                            )
                            updateHandler.update(with: updated)
                        }
                    })
            }
        )
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
