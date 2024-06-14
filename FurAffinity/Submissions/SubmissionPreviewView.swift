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
                SubmissionMainImage(
                    widthOnHeightRatio: submission.thumbnailWidthOnHeightRatio,
                    fullResolutionImageUrl: submission.thumbnailUrl,
                    fullResolutionCGImage: .constant(nil)
                )
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
