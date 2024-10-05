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
    var fullResolutionImageUrl: URL
    var displayProgress = true
    var allowZoomableSheet = true
    @Binding var fullResolutionImage: UIImage?
    @State private var showZoomableSheet = false
    @State private var errorMessage: String?
    
    var body: some View {
        GeometryReader { geometry in
            if let errorMessage {
                Centered {
                    Text("Oops, image loading failed 😞")
                    Text(errorMessage)
                        .font(.caption)
                }
            } else {
                FAImage(fullResolutionImageUrl)
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
                    .resizable()
                    .onSuccess { result in
                        fullResolutionImage = result.image
                    }
                    .sheet(isPresented: $showZoomableSheet) {
                        Zoomable(allowZoomOutBeyondFit: false) {
                            Image(uiImage: fullResolutionImage!)
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
}

#Preview {
    SubmissionMainImage(
        widthOnHeightRatio: 208/300.0,
        thumbnailImage: .init(thumbnailUrl: URL(string: "https://t.furaffinity.net/44188741@300-1634411740.jpg")!),
        fullResolutionImageUrl: URL(string: "https://d.furaffinity.net/art/annetpeas/1634411740/1634411740.annetpeas_witch2021__2_fa.png")!,
        fullResolutionImage: .constant(nil)
    )
}
