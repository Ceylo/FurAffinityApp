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
    var replyAction: @MainActor (_ parentCid: Int?, _ text: CommentReply) async throws -> Void
    
    struct ReplySession {
        let parentCid: Int?
    }
    @State private var replySession: CommentReplySession?
    @State private var fullResolutionMediaFileUrl: URL?
    
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
            },
            metadataTarget: .submissionMetadata(submission.metadata)
        )
    }
    
    var author: some View {
        AuthorHeader(
            username: submission.author,
            displayName: submission.displayAuthor,
            datetime: .init(submission.datetime, submission.naturalDatetime)
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
                mainImage
                
                Group {
                    submissionControls
                    author
                }
                .padding(.horizontal, 10)
                
                submissionDescription
                submissionComments
            }
            .listRowSeparator(.hidden)
            .listRowInsets(.init(top: 5, leading: 0, bottom: 5, trailing: 0))
        }
        .commentSheet(on: $replySession, replyAction)
        .navigationTitle(submission.title)
        .listStyle(.plain)
        .onAppear {
            prefetchAvatars(for: submission.comments)
        }
        .scrollToItem(id: submission.targetCommentId)
        .toolbar {
            RemoteContentToolbarItem(url: submission.url) {
                Button {
                    favoriteAction()
                } label: {
                    let title = submission.isFavorite ? "Unfavorite" : "Favorite"
                    let image = submission.isFavorite ? "heart.fill" : "heart"
                    Label(title, systemImage: image)
                }
                
                Button {
                    Task {
                        await MediaSaveHandler().saveMedia(atFileUrl: fullResolutionMediaFileUrl!)
                    }
                } label: {
                    Label("Save Image", systemImage: "square.and.arrow.down")
                }
                .disabled(fullResolutionMediaFileUrl == nil)
                
                Button {
                    share([fullResolutionMediaFileUrl!])
                } label: {
                    Label("Share Image", systemImage: "square.and.arrow.up")
                }
                .disabled(fullResolutionMediaFileUrl == nil)
                
                Button {
                    replySession = .init(parentCid: nil, among: [])
                } label: {
                    Label("Comment", systemImage: "bubble")
                }
                .disabled(!submission.acceptsNewComments)
            }
        }
    }
}

#Preview {
    NavigationStack {
        withAsync({ await FASubmission.demo }) {
            SubmissionView(
                submission: $0,
                avatarUrl: FAURLs.avatarUrl(for: $0.author),
                favoriteAction: {},
                replyAction: { _, _ in }
            )
        }
    }
}
