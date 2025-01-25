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
    var thumbnail: DynamicThumbnail?
    var favoriteAction: () -> Void
    var replyAction: (_ parentCid: Int?, _ text: String) async -> Bool
    
    struct ReplySession {
        let parentCid: Int?
    }
    @State private var replySession: Commenting.ReplySession?
    @State private var fullResolutionMediaFileUrl: URL?
    
    var header: some View {
        AuthoredHeaderView(
            username: submission.author,
            displayName: submission.displayAuthor,
            title: submission.title,
            avatarUrl: avatarUrl,
            datetime: .init(submission.datetime,
                            submission.naturalDatetime)
        )
    }
    
    var mainImage: some View {
        SubmissionMainImage(
            widthOnHeightRatio: submission.widthOnHeightRatio,
            thumbnailImage: thumbnail,
            fullResolutionMediaUrl: submission.fullResolutionMediaUrl,
            fullResolutionMediaFileUrl: $fullResolutionMediaFileUrl
        )
    }
    
    var submissionControls: some View {
        SubmissionControlsView(
            submissionUrl: submission.url,
            mediaFileUrl: fullResolutionMediaFileUrl,
            favoritesCount: submission.favoriteCount,
            isFavorite: submission.isFavorite,
            favoriteAction: favoriteAction,
            repliesCount: submission.comments.recursiveCount,
            acceptsNewReplies: submission.acceptsNewComments,
            replyAction: {
                replySession = .init(parentCid: nil, among: [])
            }
        )
    }
    
    var submissionDescription: some View {
        HTMLView(
            text: submission.description.convertingLinksForInAppNavigation(),
            initialHeight: 300
        )
    }
    
    @ViewBuilder
    var submissionComments: some View {
        if !submission.comments.isEmpty {
            Section {
                CommentsView(
                    comments: submission.comments,
                    highlightedCommentId: submission.targetCommentId,
                    acceptsNewReplies: submission.acceptsNewComments,
                    replyAction: { cid in
                        replySession = .init(parentCid: cid, among: submission.comments)
                    }
                )
            } header: {
                SectionHeader(text: "Comments")
            }
        }
    }
    
    var body: some View {
        List {
            Group {
                Group {
                    header
                    mainImage
                    submissionControls
                    submissionDescription
                }
                .padding(.horizontal, 10)
                
                submissionComments
            }
            .listRowSeparator(.hidden)
            .listRowInsets(.init(top: 5, leading: 0, bottom: 5, trailing: 0))
        }
        .commentSheet(on: $replySession, replyAction)
        .navigationTitle(submission.title)
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.plain)
        .onAppear {
            prefetchAvatars(for: submission.comments)
        }
        .scrollToItem(id: submission.targetCommentId)
    }
}

#Preview {
    withAsync({ await FASubmission.demo }) {
        SubmissionView(
            submission: $0,
            favoriteAction: {},
            replyAction: { _, _ in true }
        )
    }
}
