//
//  SubmissionMainImage.swift
//  FurAffinity
//
//  Created by Ceylo on 22/01/2023.
//

import SwiftUI
import FAKit
import URLImage
import Zoomable

struct SubmissionMainImage: View {
    var widthOnHeightRatio: Float
    var thumbnailImage: DynamicThumbnail?
    var fullResolutionImageUrl: URL
    var displayProgress = true
    var allowZoomableSheet = true
    @Binding var fullResolutionCGImage: CGImage?
    @State private var showZoomableSheet = false
    
    var body: some View {
        GeometryReader { geometry in
            URLImage(fullResolutionImageUrl) { progress in
                ZStack {
                    if let thumbnailUrl = thumbnailImage?.bestThumbnailUrl(for: geometry) {
                        URLImage(thumbnailUrl) { image, info in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        }
                    }
                    
                    if displayProgress {
                        LinearProgress(progress: progress ?? 0)
                    }
                }
            } failure: { error, retry in
                Centered {
                    Text("Oops, image loading failed 😞")
                    Text(error.localizedDescription)
                        .font(.caption)
                }
            } content: { image, info in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .onAppear {
                        fullResolutionCGImage = info.cgImage
                    }
                    .sheet(isPresented: $showZoomableSheet) {
                        Zoomable(allowZoomOutBeyondFit: false) {
                            image
                        }
                        .ignoresSafeArea()
                    }
                    .onTapGesture {
                        if allowZoomableSheet {
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
}

#Preview {
    SubmissionMainImage(
        widthOnHeightRatio: 208/300.0,
        thumbnailImage: .init(thumbnailUrl: URL(string: "https://t.furaffinity.net/44188741@300-1634411740.jpg")!),
        fullResolutionImageUrl: URL(string: "https://d.furaffinity.net/art/annetpeas/1634411740/1634411740.annetpeas_witch2021__2_fa.png")!,
        fullResolutionCGImage: .constant(nil)
    )
}
