//
//  SubmissionFeedItemView.swift
//  FurAffinity
//
//  Created by Ceylo on 14/11/2021.
//

import SwiftUI
import FAKit
import URLImage

protocol SubmissionHeaderView: View {
    init(preview: FASubmissionPreview, avatarUrl: URL?)
}

struct SubmissionFeedItemView<HeaderView: SubmissionHeaderView>: View {
    @EnvironmentObject var model: Model
    var submission: FASubmissionPreview
    @State private var avatarUrl: URL?
    
    var previewImage: some View {
        GeometryReader { geometry in
            if geometry.size.maxDimension > 0 {
                let url = submission.dynamicThumbnail.bestThumbnailUrl(for: geometry)
                // AsyncImage sometimes remains in empty phase when used in a List…
                URLImage(url) { progress in
                    Rectangle()
                        .foregroundColor(.white.opacity(0.1))
                } failure: { error, retry in
                    Centered {
                        Text("Oops, image loading failed 😞")
                        Text(error.localizedDescription)
                            .font(.caption)
                    }
                } content: { image, info in
                    image
                        .resizable()
                        .transition(.opacity.animation(.default.speed(2)))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.borderOverlay, lineWidth: 1)
                        }
                }
            }
        }
        .aspectRatio(CGFloat(submission.thumbnailWidthOnHeightRatio), contentMode: .fit)
        .cornerRadius(10)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HeaderView(preview: submission, avatarUrl: avatarUrl)
            .task {
                avatarUrl = await model.session?.avatarUrl(for: submission.author)
            }
            previewImage
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 0))
    }
}

struct SubmissionFeedItemView_Previews: PreviewProvider {
    static var previews: some View {
        SubmissionFeedItemView<AuthoredHeaderView>(submission: OfflineFASession.default.submissionPreviews[0])
            .environmentObject(Model.demo)
            .preferredColorScheme(.dark)
    }
}
