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

import SwiftUI
import FAKit

struct SubmissionMainImage: View {
    var widthOnHeightRatio: Float
    var thumbnailImage: DynamicThumbnail?
    var fullResolutionMediaUrl: URL
    var displayProgress = true
    var allowZoomableSheet = true
    @Binding var fullResolutionMediaFileUrl: URL?

    // Not private: skipstone can't bridge a private @State/@Environment.
    @State var errorMessage: String?
    @State var showZoomableSheet = false

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
                    .fadingSheet(isPresented: $showZoomableSheet) {
                        zoomableViewer
                    }
                    // Only when zooming is allowed, so this doesn't silently eat taps
                    // meant for a wrapping handler — same reason as iOS.
                    .applying {
                        if allowZoomableSheet {
                            // Only once there is something to zoom: the viewer has no
                            // content of its own, so opening it early is a black screen.
                            // iOS gates on its loaded image the same way.
                            $0.onTapGesture {
                                if fullResolutionMediaFileUrl != nil {
                                    showZoomableSheet = true
                                }
                            }
                        } else {
                            $0
                        }
                    }
            }
        }
        .aspectRatio(CGFloat(widthOnHeightRatio), contentMode: .fit)
        // Publishing the file URL is what enables Save and Share. `FAImage` owns the
        // load and reports no path, so ask the store directly — it coalesces with the
        // load already in flight, so this costs no second download.
        //
        // Skipped where the caller can't use it: `SubmissionPreviewView` and the audio
        // cover pass `.constant(nil)`, and staging a copy of every previewed thumbnail
        // for a binding that discards it is pure waste.
        .task(id: fullResolutionMediaUrl) {
            guard allowZoomableSheet else { return }
            fullResolutionMediaFileUrl = await FAImageStore.shared.namedFileUrl(for: fullResolutionMediaUrl)
        }
    }

    // No close button: `Zoomable` dismisses on a downward pull the way iOS's sheet does,
    // and SkipUI's presentation still dismisses on the system Back gesture.
    private var zoomableViewer: some View {
        Zoomable {
            FAImage(fullResolutionMediaUrl)
        }
        .contentAspectRatio(Double(widthOnHeightRatio))
        .initialZoomLevel(.boundedFill(maxScaledFit: 2))
        .primaryZoomLevel(.fill)
        .secondaryZoomLevel(.fit)
        .ignoresSafeArea()
    }
}
