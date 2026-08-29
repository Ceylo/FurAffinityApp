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
    @State var showZoomableCover = false

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
                    // iOS presents the viewer from a `fadingSheet` (UIKit-backed).
                    .fullScreenCover(isPresented: $showZoomableCover) {
                        zoomableCover
                    }
                    // Only when zooming is allowed, so this doesn't silently eat taps
                    // meant for a wrapping handler — same reason as iOS.
                    .applying {
                        if allowZoomableSheet {
                            // Only once there is something to zoom: the cover has no
                            // content of its own, so opening it early is a black screen.
                            // iOS gates on its loaded image the same way.
                            $0.onTapGesture {
                                if fullResolutionMediaFileUrl != nil {
                                    showZoomableCover = true
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

    private var zoomableCover: some View {
        ZStack(alignment: .topLeading) {
            Color.black
                .ignoresSafeArea()

            Zoomable {
                FAImage(fullResolutionMediaUrl)
            }
            .contentAspectRatio(Double(widthOnHeightRatio))
            .initialZoomLevel(.boundedFill(maxScaledFit: 2))
            .primaryZoomLevel(.fill)
            .secondaryZoomLevel(.fit)
            .ignoresSafeArea()

            // fullScreenCover has no navigation chrome, so it needs its own way out.
            Button {
                showZoomableCover = false
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.white)
                    .padding(16)
            }
        }
    }
}
