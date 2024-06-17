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
    
    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                AuthoredHeaderView(
                    username: submission.author,
                    displayName: submission.displayAuthor,
                    title: submission.title,
                    avatarUrl: avatarUrl,
                    datetime: nil
                )
                GeometryReader { geometry in
                    SubmissionMainImage(
                        widthOnHeightRatio: submission.thumbnailWidthOnHeightRatio,
                        fullResolutionImageUrl: submission.dynamicThumbnail.bestThumbnailUrl(for: geometry),
                        displayProgress: false,
                        fullResolutionCGImage: .constant(nil)
                    )
                }
                .aspectRatio(CGFloat(submission.thumbnailWidthOnHeightRatio), contentMode: .fit)
            }
            .padding(.horizontal, 10)
            .padding(.top, 5)
        }
        .navigationTitle(submission.title)
    }
}

#Preview {
    SubmissionPreviewView(
        submission: FASubmissionPreview.demo
    )
}
