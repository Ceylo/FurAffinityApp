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
    
    private var username: String? {
        previewData?.author ?? FAURLs.usernameFrom(userUrl: url)
    }
    
    var body: some View {
        PreviewableRemoteView(
            url: url,
            dataSource: { url in
                await model.session?.submission(for: url)
            },
            preview: {
                previewData.map {
                    SubmissionPreviewView(
                        submission: $0,
                        avatarUrl: FAURLs.avatarUrl(for: $0.author)
                    )
                }
            },
            view: { submission, updateHandler in
                SubmissionView(
                    submission: submission,
                    avatarUrl: FAURLs.avatarUrl(for: submission.author),
                    thumbnail: previewData?.dynamicThumbnail,
                    favoriteAction: {
                        updateHandler.update(with: submission.togglingFavorite())
                        Task {
                            let updated = try await model.toggleFavorite(for: submission)
                            updateHandler.update(with: updated)
                        }
                    },
                    replyAction: { parentCid, reply in
                        let updated = try await model.postComment(
                            on: submission,
                            replytoCid: parentCid,
                            contents: reply.commentText
                        )
                        updateHandler.update(with: updated)
                    }
                )
            }
        )
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
