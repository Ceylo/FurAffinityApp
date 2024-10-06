//
//  SubmissionMainImage.swift
//  FurAffinity
//
//  Created by Ceylo on 22/01/2023.
//

import SwiftUI
import FAKit
import Kingfisher
import Zoomable

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
    
    var body: some View {
        GeometryReader { geometry in
            if let errorMessage {
                Centered {
                    Text("Oops, image loading failed 😞")
                    Text(errorMessage)
                        .font(.caption)
                }
            } else {
                FAAnimatedImage(fullResolutionMediaUrl)
                    .placeholder { progress in
                        ZStack {
                            if let thumbnailUrl = thumbnailImage?.bestThumbnailUrl(for: geometry) {
                                FAImage(thumbnailUrl)
                                    .resizable()
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
                    .sheet(isPresented: $showZoomableSheet) {
                        Zoomable(allowZoomOutBeyondFit: false) {
                            FAAnimatedImage(fullResolutionMediaUrl)
                                .frame(width: fullResolutionImage!.size.width, height: fullResolutionImage!.size.height)
                        }
                        .ignoresSafeArea()
                    }
                    .aspectRatio(contentMode: .fit)
                    .onTapGesture {
                        if allowZoomableSheet && fullResolutionImage != nil {
                            showZoomableSheet = true
                        }
                    }
            }
        }
        .aspectRatio(CGFloat(widthOnHeightRatio), contentMode: .fit)
        .cornerRadius(10)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.borderOverlay, lineWidth: 1)
        }
    }
    
    func prepareFullResolutionMedia(sourceUrl: URL, loadedImage: UIImage) {
        let cacheKey = sourceUrl.cacheKey
        let path = ImageCache.default.cachePath(forKey: cacheKey)
        let fileManager = FileManager.default
        precondition(ImageCache.default.diskStorage.isCached(forKey: cacheKey))
        precondition(fileManager.fileExists(atPath: path))
        
        let filename = sourceUrl.lastPathComponent
        let pathWithExtension = URL.temporaryDirectory.appending(component: filename)
        do {
            if fileManager.fileExists(atPath: pathWithExtension.path(percentEncoded: false)) {
                try fileManager.removeItem(at: pathWithExtension)
            }
            try fileManager.copyItem(atPath: path, toPath: pathWithExtension.path(percentEncoded: false))
            fullResolutionMediaFileUrl = pathWithExtension
            fullResolutionImage = loadedImage
        } catch {
            logger.error("\(error, privacy: .public)")
        }
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
