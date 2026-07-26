//
//  SubmissionMainImage.swift
//  FurAffinityUI (Android)
//
//  Android counterpart of the iOS `SubmissionMainImage`. Same name and signature, so
//  `SubmissionView` / `SubmissionPreviewView` symlink verbatim; the body is rebuilt on
//  `FAImage` because the iOS one is written against Kingfisher's `KFImageProtocol`
//  (`.placeholder(progress:)`, `.waitForCache()`, `.onSuccess`), which has no Android
//  equivalent.
//
//  The zoomable full-screen viewer arrives in step 4; `allowZoomableSheet` is accepted
//  and ignored until then.
//

import SwiftUI
import FAKit

struct SubmissionMainImage: View {
    var widthOnHeightRatio: Float
    var thumbnailImage: DynamicThumbnail?
    var fullResolutionMediaUrl: URL
    var displayProgress = true
    var allowZoomableSheet = true
    @Binding var fullResolutionMediaFileUrl: URL?

    // @State on a bridged view must be internal, not private (Skip inventory #5).
    @State var errorMessage: String?

    var body: some View {
        GeometryReader { geometry in
            if let errorMessage {
                Centered {
                    VStack(spacing: 10) {
                        Text("Oops, image loading failed 😞")
                        Text(errorMessage)
                            .font(.caption)
                    }
                }
            } else {
                FAImage(fullResolutionMediaUrl)
                    .placeholder {
                        if let thumbnailUrl = thumbnailImage?.bestThumbnailUrl(for: geometry) {
                            FAImage(thumbnailUrl)
                                .aspectRatio(contentMode: .fit)
                        }
                    }
                    .onFailure { error in
                        errorMessage = error.localizedDescription
                    }
                    .aspectRatio(contentMode: .fit)
            }
        }
        .aspectRatio(CGFloat(widthOnHeightRatio), contentMode: .fit)
        // Publishing the file URL is what enables Save and Share. `FAImage` owns the
        // load and reports no path, so ask the store directly — it coalesces with the
        // load already in flight, so this costs no second download.
        .task(id: fullResolutionMediaUrl) {
            fullResolutionMediaFileUrl = await FAImageStore.shared.fileUrl(for: fullResolutionMediaUrl)
        }
    }
}
