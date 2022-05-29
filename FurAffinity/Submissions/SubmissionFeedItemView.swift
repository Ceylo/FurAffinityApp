//
//  SubmissionFeedItemView.swift
//  FurAffinity
//
//  Created by Ceylo on 14/11/2021.
//

import SwiftUI
import FAKit
import URLImage



struct SubmissionFeedItemView: View {
    @EnvironmentObject var model: Model
    var submission: FASubmissionPreview
    @State private var avatarUrl: URL?
    
    var previewImage: some View {
        GeometryReader { geometry in
            // AsyncImage sometimes remains in empty phase when used in a List…
            URLImage(submission.bestThumbnailUrl(for: UInt(geometry.size.maxDimension))) { progress in
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
            .environment(\.urlImageOptions, URLImageOptions(loadOptions: [.loadImmediately, .loadOnAppear, .cancelOnDisappear]))
        }
        .aspectRatio(CGFloat(submission.thumbnailWidthOnHeightRatio), contentMode: .fit)
        .cornerRadius(10)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SubmissionHeaderView(author: submission.displayAuthor,
                                 title: submission.title,
                                 avatarUrl: avatarUrl)
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
        SubmissionFeedItemView(submission: OfflineFASession.default.submissionPreviews[0])
            .environmentObject(Model.demo)
            .preferredColorScheme(.dark)
    }
}
