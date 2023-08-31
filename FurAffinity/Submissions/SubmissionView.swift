//
//  SubmissionView.swift
//  FurAffinity
//
//  Created by Ceylo on 30/03/2023.
//

import SwiftUI
import FAKit

struct SubmissionView: View {
    var submission: FASubmission
    var avatarUrl: URL?
    var description: AttributedString?
    var favoriteAction: () -> Void
    var replyAction: (_ parentCid: Int?, _ text: String) -> Void
    
    struct ReplySession {
        let parentCid: Int?
    }
    @State private var replySession: Commenting.ReplySession?
    @State private var fullResolutionCGImage: CGImage?
    
    var header: some View {
        HeaderView(
            username: submission.author,
            displayName: submission.displayAuthor,
            title: submission.title,
            avatarUrl: avatarUrl,
            datetime: .init(submission.datetime,
                            submission.naturalDatetime)
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            SubmissionMainImage(
                widthOnHeightRatio: submission.widthOnHeightRatio,
                fullResolutionImageUrl: submission.fullResolutionImageUrl,
                fullResolutionCGImage: $fullResolutionCGImage
            )
            
            SubmissionControlsView(
                submissionUrl: submission.url,
                fullResolutionImage: fullResolutionCGImage,
                isFavorite: submission.isFavorite,
                favoriteAction: favoriteAction,
                replyAction: {
                    replySession = .init(parentCid: nil, among: [])
                }
            )
            
            if let description {
                TextView(text: description, initialHeight: 300)
            }
            
            if !submission.comments.isEmpty {
                VStack {
                    Text("Comments")
                        .font(.headline)
                    CommentsView(
                        comments: submission.comments,
                        replyAction: { cid in
                            replySession = .init(parentCid: cid, among: submission.comments)
                        }
                    )
                }
            }
        }
        .padding(10)
        .commentSheet(on: $replySession, replyAction)
        .navigationTitle(submission.title)
    }
}

struct SubmissionView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            SubmissionView(
                submission: FASubmission.demo,
                favoriteAction: {},
                replyAction: { parentCid,text in }
            )
        }
    }
}
