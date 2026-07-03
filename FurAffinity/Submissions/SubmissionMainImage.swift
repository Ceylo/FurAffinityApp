//
//  SubmissionMainImage.swift
//  FurAffinity
//
//  Created by Ceylo on 22/01/2023.
//

import SwiftUI
import FAKit
import Kingfisher

// KFAnimatedImage may display with an incorrect aspect ratio
// on the initial display, so we don't use it unless needed.
private func canAnimate(_ url: URL?) -> Bool {
    url?.pathExtension.lowercased() == "gif"
}

struct SubmissionMainImage: View {
    var widthOnHeightRatio: Float
    var thumbnailImage: DynamicThumbnail?
    var fullResolutionMediaUrl: URL
    var displayProgress = true
    var allowZoomableSheet = true
    @Binding var fullResolutionMediaFileUrl: URL?
    @State private var showZoomableSheet = false
    @State private var errorMessage: String?
    @State private var fullResolutionImage: UIImage?
    
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
                Group {
                    if canAnimate(fullResolutionMediaUrl) {
                        configure(FAAnimatedImage(fullResolutionMediaUrl), geometry: geometry)
                    } else {
                        configure(FAImage(fullResolutionMediaUrl), geometry: geometry)
                    }
                }
                .fadingSheet(isPresented: $showZoomableSheet) {
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
                    .initialZoomLevel(.boundedFill(maxScaledFit: 2))
                    .primaryZoomLevel(.fill)
                    .secondaryZoomLevel(.fit)
                    .ignoresSafeArea()
                }
                .aspectRatio(contentMode: .fit)
                // Only attach the tap gesture when zooming is allowed; otherwise it
                // would silently consume taps meant for a wrapping handler (e.g. the
                // text cover's tap-to-read).
                .applying {
                    if allowZoomableSheet {
                        $0.onTapGesture {
                            if fullResolutionImage != nil {
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
    }
    
    func prepareFullResolutionMedia(sourceUrl: URL, loadedImage: UIImage) {
        guard let fileUrl = try? cachedImageFileURL(for: sourceUrl) else {
            return
        }
        fullResolutionMediaFileUrl = fileUrl
        fullResolutionImage = loadedImage
    }
}

#Preview {
    SubmissionMainImage(
        widthOnHeightRatio: 208/300.0,
        thumbnailImage: .init(thumbnailUrl: URL(string: "https://t.furaffinity.net/44188741@300-1634411740.jpg")!),
        fullResolutionMediaUrl: URL(string: "https://d.furaffinity.net/art/annetpeas/1634411740/1634411740.annetpeas_witch2021__2_fa.png")!,
        fullResolutionMediaFileUrl: .constant(nil)
    )
}
