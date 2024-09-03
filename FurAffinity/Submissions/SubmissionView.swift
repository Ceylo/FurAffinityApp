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
    var replyAction: (_ parentCid: Int?, _ text: String) -> Void
    
    struct ReplySession {
        let parentCid: Int?
    }
    @State private var replySession: Commenting.ReplySession?
    @State private var fullResolutionCGImage: CGImage?
    
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
    
    var body: some View {
        List {
            Group {
                Group {
                    header
                    SubmissionMainImage(
                        widthOnHeightRatio: submission.widthOnHeightRatio,
                        thumbnailImage: thumbnail,
                        fullResolutionImageUrl: submission.fullResolutionImageUrl,
                        fullResolutionCGImage: $fullResolutionCGImage
                    )
                    
                    SubmissionControlsView(
                        submissionUrl: submission.url,
                        fullResolutionImage: fullResolutionCGImage,
                        favoritesCount: submission.favoriteCount,
                        isFavorite: submission.isFavorite,
                        favoriteAction: favoriteAction,
                        repliesCount: submission.comments.recursiveCount,
                        replyAction: {
                            replySession = .init(parentCid: nil, among: [])
                        }
                    )
                    .foregroundStyle(Color.accentColor)
                    
                    HTMLView(
                        text: submission.description.convertingLinksForInAppNavigation(),
                        initialHeight: 300
                    )
                }
                .padding(.horizontal, 10)
                
                if !submission.comments.isEmpty {
                    Section {
                        CommentsView(
                            comments: submission.comments,
                            replyAction: { cid in
                                replySession = .init(parentCid: cid, among: submission.comments)
                            }
                        )
                        
                    } header: {
                        SectionHeader(text: "Comments")
                    }
                }
            }
            .listRowSeparator(.hidden)
            .listRowInsets(.init(top: 5, leading: 0, bottom: 5, trailing: 0))
        }
        .commentSheet(on: $replySession, replyAction)
        .navigationTitle(submission.title)
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.plain)
    }
}

struct SubmissionView_Previews: PreviewProvider {
    static var previews: some View {
        SubmissionView(
            submission: FASubmission.demo,
            favoriteAction: {},
            replyAction: { parentCid,text in }
        )
    }
}
