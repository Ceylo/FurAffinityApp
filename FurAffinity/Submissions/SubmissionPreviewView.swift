//
//  SubmissionPreviewView.swift
//  FurAffinity
//
//  Created by Ceylo on 30/03/2023.
//

import SwiftUI
import FAKit

// For a smooth transition, this should mimic the layout of SubmissionView,
// but with the data from preview only. Once the full data is available, this gets
// swapped with a SubmissionView.
struct SubmissionPreviewView: View {
    var submission: FASubmissionPreview
    var avatarUrl: URL?
    
    var mainImage: some View {
        GeometryReader { geometry in
            SubmissionMainImage(
                widthOnHeightRatio: submission.thumbnailWidthOnHeightRatio,
                fullResolutionMediaUrl: submission.dynamicThumbnail.bestThumbnailUrl(for: geometry),
                displayProgress: false,
                allowZoomableSheet: false,
                fullResolutionMediaFileUrl: .constant(nil)
            )
        }
        .aspectRatio(CGFloat(submission.thumbnailWidthOnHeightRatio), contentMode: .fit)
    }
    
    var submissionControlsSpace: some View {
        SubmissionControlsView(
            submissionUrl: submission.url,
            favoritesCount: 0,
            isFavorite: false,
            favoriteAction: {},
            repliesCount: 0,
            acceptsNewReplies: true,
            replyAction: {}
        )
        .hidden()
    }
    
    var author: some View {
        AuthorHeader(
            username: submission.author,
            displayName: submission.displayAuthor
        )
    }
    
    var body: some View {
        List {
            Group {
                mainImage
                    .padding(.horizontal, -10)
                submissionControlsSpace
                author
            }
            .padding(.horizontal, 10)
            .listRowSeparator(.hidden)
            .listRowInsets(.init(top: 5, leading: 0, bottom: 5, trailing: 0))
        }
        .listStyle(.plain)
        .navigationTitle(submission.title)
    }
}

#Preview {
    NavigationStack {
        SubmissionPreviewView(
            submission: FASubmissionPreview.demo
        )
    }
}
