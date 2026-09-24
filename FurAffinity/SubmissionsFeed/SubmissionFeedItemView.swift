//
//  SubmissionFeedItemView.swift
//  FurAffinity
//
//  Created by Ceylo on 14/11/2021.
//

import Foundation
import SwiftUI
import FAKit
import Kingfisher

protocol SubmissionHeaderView: View {
    @MainActor
    init(preview: FASubmissionPreview)
}

struct SubmissionFeedItemView<HeaderView: SubmissionHeaderView>: View {
    var submission: FASubmissionPreview
    
    @State var errorMessage: String?
    
    var previewImage: some View {
        GeometryReader { geometry in
            let size = geometry.faSize
            if size.maxDimension > 0 {
                let url = submission.dynamicThumbnail.bestThumbnailUrl(for: size)
                if let errorMessage {
                    Centered {
                        VStack(spacing: 10) {
                            Text("Oops, image loading failed 😞")
                            Text(errorMessage)
                                .font(.caption)
                        }
                    }
                } else {
                    FAImage(url)
                        .placeholder {
                            Rectangle()
                                .foregroundColor(.white.opacity(0.1))
                        }
                        .onFailure { error in
                            errorMessage = error.localizedDescription
                        }
                        .fade(duration: 0.25)
                        .onAppear {
                            Task {
                                await controlCacheBehavior(for: url)
                            }
                        }
                }
            }
        }
        .aspectRatio(Double(submission.thumbnailWidthOnHeightRatio), contentMode: .fit)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HeaderView(preview: submission)
                .padding(.horizontal, 10)
            previewImage
        }
    }
    
    /// Diagnostic only: is this row's thumbnail in flight, cached, or not started?
    func controlCacheBehavior(for url: URL) async {
        let downloadStartDate = await DownloadDelegate.shared.downloadStartDate(for: url)
        let isCached = ImageCache.default.imageCachedType(forKey: url.cacheKey) != .none
        if let downloadStartDate {
            let elapsedMs = Int(abs(downloadStartDate.timeIntervalSinceNow * 1000))
            logger.info("Thumbnail download for \"\(submission.title)\" started \(elapsedMs)ms ago")
        } else if !isCached {
            logger.info("Thumbnail for \"\(submission.title)\" isn't downloading yet")
        }
    }
}

#Preview {
    SubmissionFeedItemView<TitleAuthorHeader>(submission: OfflineFASession.default.submissionPreviews[0])
        .preferredColorScheme(.dark)
}
