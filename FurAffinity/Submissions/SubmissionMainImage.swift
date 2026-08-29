//
//  SubmissionMainImage.swift
//  FurAffinity
//
//  Created by Ceylo on 22/01/2023.
//
//  One file for both platforms. Only two things genuinely differ, and they are the two
//  `#if FA_SKIP_MODULE` members below: how the image is *loaded* (iOS drives Kingfisher's
//  `KFImageProtocol`, Android `FAImage` + `FAImageStore`), and what goes *inside* the
//  zoom viewer — iOS frames the content at the loaded image's pixel size, which is what
//  feeds `UIHostingController.intrinsicContentSize` and hence every zoom ratio, while
//  Android states the ratio directly. Those two must not be unified: changing iOS's zoom
//  base would change the meaning of its `maximumZoomScale = 10`.
//
//  Accepted difference: `displayProgress` draws nothing on Android — `FAImageStore`
//  reports no byte progress across JNI.
//

import SwiftUI
import FAKit
#if !FA_SKIP_MODULE
import Kingfisher

// KFAnimatedImage may display with an incorrect aspect ratio
// on the initial display, so we don't use it unless needed.
private func canAnimate(_ url: URL?) -> Bool {
    url?.pathExtension.lowercased() == "gif"
}
#endif

struct SubmissionMainImage: View {
    var widthOnHeightRatio: Float
    var thumbnailImage: DynamicThumbnail?
    var fullResolutionMediaUrl: URL
    var displayProgress = true
    var allowZoomableSheet = true
    @Binding var fullResolutionMediaFileUrl: URL?

    // Every one of these is declared outside all `#if`s, and none is private: skipstone
    // can't bridge a private `@State`, and it skips conditional blocks when generating
    // the view's bridge — a `@State` inside one silently never recomposes.
    @State var errorMessage: String?
    @State var showZoomableSheet = false
    /// Set once the viewer would have something to show. Each platform decides that
    /// differently, but the tap gate itself is shared.
    @State var canPresentViewer = false
    /// iOS only — the loaded image is what the viewer sizes itself from.
    @State var fullResolutionImage: UIImage?

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
                loader(geometry: geometry)
                    .aspectRatio(contentMode: .fit)
                    .fadingSheet(isPresented: $showZoomableSheet) {
                        zoomableViewer
                    }
                    // Only attach the tap gesture when zooming is allowed; otherwise it
                    // would silently consume taps meant for a wrapping handler (e.g. the
                    // text cover's tap-to-read).
                    .applying {
                        if allowZoomableSheet {
                            // And only once there is something to zoom: the viewer has no
                            // content of its own, so opening it early is a black screen.
                            $0.onTapGesture {
                                if canPresentViewer {
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
        .applying { preparingFullResolutionMedia($0) }
    }

    /// The zoom-level chain is the same on both platforms; the `Zoomable` it is applied
    /// to is not, so it takes that value rather than being repeated in each branch.
    private func configuredViewer<Content: View>(_ zoomable: Zoomable<Content>) -> some View {
        zoomable
            .initialZoomLevel(.boundedFill(maxScaledFit: 2))
            .primaryZoomLevel(.fill)
            .secondaryZoomLevel(.fit)
            .ignoresSafeArea()
    }

#if FA_SKIP_MODULE

    @ViewBuilder
    private func loader(geometry: GeometryProxy) -> some View {
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
    }

    /// Publishing the file URL is what enables Save and Share. `FAImage` owns the load
    /// and reports no path, so ask the store directly — it coalesces with the load
    /// already in flight, so this costs no second download.
    ///
    /// Skipped where the caller can't use it: `SubmissionPreviewView` and the audio cover
    /// pass `.constant(nil)`, and staging a copy of every previewed thumbnail for a
    /// binding that discards it is pure waste.
    private func preparingFullResolutionMedia(_ view: some View) -> some View {
        view.task(id: fullResolutionMediaUrl) {
            guard allowZoomableSheet else { return }
            fullResolutionMediaFileUrl = await FAImageStore.shared.namedFileUrl(for: fullResolutionMediaUrl)
            canPresentViewer = fullResolutionMediaFileUrl != nil
        }
    }

    /// No close button: `Zoomable` dismisses on a downward pull the way iOS's sheet does,
    /// and SkipUI's presentation still dismisses on the system Back gesture.
    private var zoomableViewer: some View {
        configuredViewer(
            Zoomable {
                FAImage(fullResolutionMediaUrl)
            }
            .contentAspectRatio(Double(widthOnHeightRatio))
        )
    }

#else

    private func configure(_ image: some KFImageProtocol, geometry: GeometryProxy) -> some KFImageProtocol {
        image
            .placeholder { progress in
                ZStack {
                    if let thumbnailUrl = thumbnailImage?.bestThumbnailUrl(for: geometry) {
                        FAImage(thumbnailUrl)
                            .aspectRatio(contentMode: .fit)
                    }

                    if displayProgress {
                        LinearProgress(progress: Float(progress.fractionCompleted))
                    }
                }
            }
            .onFailure { error in
                errorMessage = error.localizedDescription
            }
            .waitForCache()
            .onSuccess { result in
                prepareFullResolutionMedia(
                    sourceUrl: fullResolutionMediaUrl,
                    loadedImage: result.image
                )
            }
    }

    @ViewBuilder
    private func loader(geometry: GeometryProxy) -> some View {
        if canAnimate(fullResolutionMediaUrl) {
            configure(FAAnimatedImage(fullResolutionMediaUrl), geometry: geometry)
        } else {
            configure(FAImage(fullResolutionMediaUrl), geometry: geometry)
        }
    }

    /// Nothing to attach: Kingfisher's `onSuccess` already publishes both, through
    /// `prepareFullResolutionMedia`.
    private func preparingFullResolutionMedia(_ view: some View) -> some View {
        view
    }

    func prepareFullResolutionMedia(sourceUrl: URL, loadedImage: UIImage) {
        guard let fileUrl = try? cachedImageFileURL(for: sourceUrl) else {
            return
        }
        fullResolutionMediaFileUrl = fileUrl
        fullResolutionImage = loadedImage
        canPresentViewer = true
    }

    private var zoomableViewer: some View {
        configuredViewer(
            Zoomable {
                Group {
                    if canAnimate(fullResolutionMediaUrl) {
                        FAAnimatedImage(fullResolutionMediaUrl)
                    } else {
                        FAImage(fullResolutionMediaUrl)
                    }
                }
                .frame(
                    width: fullResolutionImage!.size.width,
                    height: fullResolutionImage!.size.height
                )
            }
        )
    }

#endif
}

#if !FA_SKIP_MODULE
#Preview {
    SubmissionMainImage(
        widthOnHeightRatio: 208/300.0,
        thumbnailImage: .init(thumbnailUrl: URL(string: "https://t.furaffinity.net/44188741@300-1634411740.jpg")!),
        fullResolutionMediaUrl: URL(string: "https://d.furaffinity.net/art/annetpeas/1634411740/1634411740.annetpeas_witch2021__2_fa.png")!,
        fullResolutionMediaFileUrl: .constant(nil)
    )
}
#endif
