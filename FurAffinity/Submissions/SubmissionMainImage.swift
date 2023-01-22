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
    var fullResolutionImageUrl: URL
    @Binding var fullResolutionCGImage: CGImage?
    @State private var showZoomableSheet = false
    
    var body: some View {
        URLImage(fullResolutionImageUrl) { progress in
            Centered {
                CircularProgress(progress: CGFloat(progress ?? 0))
                    .frame(width: 100, height: 100)
            }
            .aspectRatio(CGFloat(widthOnHeightRatio),
                         contentMode: .fit)
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
                .transition(.opacity.animation(.default.speed(2)))
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
                    showZoomableSheet = true
                }
        }
        .cornerRadius(10)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.borderOverlay, lineWidth: 1)
        }
    }
}

struct SubmissionMainImage_Previews: PreviewProvider {
    static var previews: some View {
        SubmissionMainImage(
            widthOnHeightRatio: 1,
            fullResolutionImageUrl: URL(string: "https://d.furaffinity.net/art/annetpeas/1634411740/1634411740.annetpeas_witch2021__2_fa.png")!,
            fullResolutionCGImage: .constant(nil)
        )
    }
}
