//
//  SubmissionFeedItemView.swift
//  FurAffinity
//
//  Created by Ceylo on 14/11/2021.
//

import SwiftUI
import FAKit
import Kingfisher

protocol SubmissionHeaderView: View {
    @MainActor
    init(preview: FASubmissionPreview, avatarUrl: URL?)
}

struct SubmissionFeedItemView<HeaderView: SubmissionHeaderView>: View {
    var submission: FASubmissionPreview
    
    @State private var errorMessage: String?
    
    var previewImage: some View {
        GeometryReader { geometry in
            if geometry.size.maxDimension > 0 {
                let url = submission.dynamicThumbnail.bestThumbnailUrl(for: geometry)
                if let errorMessage {
                    Centered {
                        Text("Oops, image loading failed 😞")
                        Text(errorMessage)
                            .font(.caption)
                    }
                } else {
                    FAImage(url)
                        .placeholder {
                            Rectangle()
                                .foregroundColor(.white.opacity(0.1))
                        }
                        .resizable()
                        .onFailure { error in
                            errorMessage = error.localizedDescription
                        }
                        .fade(duration: 0.25)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.borderOverlay, lineWidth: 1)
                        }
                        .onAppear {
                            controlCacheBehavior(for: url)
                        }
                }
            }
        }
        .aspectRatio(CGFloat(submission.thumbnailWidthOnHeightRatio), contentMode: .fit)
        .cornerRadius(10)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HeaderView(preview: submission, avatarUrl: FAURLs.avatarUrl(for: submission.author))
            previewImage
        }
        .padding(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 0))
    }
    
    func controlCacheBehavior(for url: URL) {
        let cacheType = ImageCache.default.imageCachedType(forKey: url.cacheKey)
        let downloadStartDate = DownloadDelegate.shared.downloading[url]
        if let downloadStartDate {
            let elapsedMs = Int(abs(downloadStartDate.timeIntervalSinceNow * 1000))
            logger.info("Thumbnail for \(submission.title, privacy: .public) downloaded started \(elapsedMs)ms ago")
        } else if cacheType == .none {
            logger.info("Thumbnail for \(submission.title, privacy: .public) isn't downloading yet")
        }
    }
}

#Preview {
    SubmissionFeedItemView<AuthoredHeaderView>(submission: OfflineFASession.default.submissionPreviews[0])
        .preferredColorScheme(.dark)
}
