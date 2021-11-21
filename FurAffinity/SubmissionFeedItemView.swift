//
//  SubmissionFeedItemView.swift
//  FurAffinity
//
//  Created by Ceylo on 14/11/2021.
//

import SwiftUI
import FAKit
import URLImage

extension CGSize {
    var maxDimension: CGFloat { max(width, height) }
}

struct SubmissionFeedItemView: View {
    @Binding var submission: FASubmissionPreview
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(submission.displayAuthor)  ")
                    .font(.headline)
                +
                Text(submission.title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding([.leading, .trailing], 10)
            .padding([.bottom, .top], 10)
            
            GeometryReader { geometry in
                // AsyncImage sometimes remains in empty phase when used in a List…
                URLImage(submission.bestThumbnailUrl(for: UInt( geometry.size.maxDimension))) { progress in
                    EmptyView()
                } failure: { error, retry in
                    Centered {
                        Text("Oops, image loading failed 😞")
                        Text(error.localizedDescription)
                            .font(.caption)
                    }
                } content: { image, info in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .transition(.opacity.animation(.default.speed(2)))
                }
                
            }
            .aspectRatio(CGFloat(submission.thumbnailWidthOnHeightRatio), contentMode: .fit)
        }
    }
}

struct SubmissionFeedItemView_Previews: PreviewProvider {
    static var previews: some View {
        SubmissionFeedItemView(submission: .constant(OfflineFASession.default.submissionPreviews[0]))
            .preferredColorScheme(.dark)
    }
}
