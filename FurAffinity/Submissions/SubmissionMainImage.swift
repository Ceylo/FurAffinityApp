//
//  SubmissionMainImage.swift
//  FurAffinity
//
//  Created by Ceylo on 22/01/2023.
//
//  One file for both platforms. Three seams stay behind `#if FA_SKIP_MODULE`:
//
//  - `loader`, the obvious one (`KFImage` vs the `FAImageView` stand-in).
//  - `zoomableViewer`'s content, the one that isn't: iOS sizes it in pixels because that
//    is what feeds `UIHostingController.intrinsicContentSize` and hence every zoom ratio,
//    so unifying it with Android's aspect ratio would change the meaning of iOS's
//    `maximumZoomScale = 10` (which `Zoomable+Android` mirrors).
//  - `preparingFullResolutionMedia`, which exists only because `FAImageView` has no
//    `onSuccess` to publish the file URL from, so Android asks for it in a `.task`.
//
//  Accepted difference: `displayProgress` draws nothing on Android — the OkHttp
//  transport reports no byte progress across JNI.
//

import SwiftUI
import FAKit
import Kingfisher

#if !FA_SKIP_MODULE

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

    // All outside every `#if`, none private: skipstone bridges neither a private
    // `@State` nor one inside a conditional block, and silently never recomposes it.
    @State var errorMessage: String?
    @State var showZoomableSheet = false
    /// Set once the viewer would have something to show — differently per platform,
    /// which is what lets the tap gate be shared.
    @State var canPresentViewer = false
    /// iOS only: what the viewer sizes itself from.
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
                    // Only when zooming is allowed, or it silently eats taps meant for
                    // a wrapping handler — the story cover's tap-to-read. And only once
                    // there is something to zoom: opening early is a black screen.
                    .applying {
                        if allowZoomableSheet {
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

    /// What shows until the full-resolution media arrives. Shared: only the progress
    /// bar iOS draws over it is platform-specific.
    @ViewBuilder
    private func thumbnailPlaceholder(geometry: GeometryProxy) -> some View {
        if let thumbnailUrl = thumbnailImage?.bestThumbnailUrl(for: geometry) {
            FAImage(thumbnailUrl)
                .aspectRatio(contentMode: .fit)
        }
    }

    /// Takes the `Zoomable` as a value so the shared chain isn't repeated in each
    /// branch: the modifiers are `Zoomable`-typed and the two differ in their generic.
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
                thumbnailPlaceholder(geometry: geometry)
            }
            .onFailure { error in
                errorMessage = error.localizedDescription
            }
    }

    /// The file URL is what enables Save and Share. `FAImageView` has no `onSuccess`
    /// to hang this on, so ask Kingfisher directly; the request coalesces with the
    /// load already in flight and normally resolves straight out of the disk cache.
    ///
    /// Skipped where the caller can't use it — `SubmissionPreviewView` and the audio
    /// cover pass `.constant(nil)` — rather than copying every thumbnail.
    private func preparingFullResolutionMedia(_ view: some View) -> some View {
        view.task(id: fullResolutionMediaUrl) {
            guard allowZoomableSheet else { return }
            fullResolutionMediaFileUrl = try? await KingfisherManager.shared
                .retrieveFAImageFile(with: fullResolutionMediaUrl)
            canPresentViewer = fullResolutionMediaFileUrl != nil
        }
    }

    /// No close button: `Zoomable` dismisses on a downward pull as iOS's sheet does, and
    /// the presentation still answers the system Back gesture.
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
                    thumbnailPlaceholder(geometry: geometry)

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

    /// Nothing to attach: Kingfisher's `onSuccess` publishes both, in
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
