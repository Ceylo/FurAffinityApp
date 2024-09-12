//
//  SubmissionControlsView.swift
//  FurAffinity
//
//  Created by Ceylo on 27/11/2021.
//

import SwiftUI

struct SubmissionControlsView: View {
    var submissionUrl: URL
    var fullResolutionImage: CGImage?
    var favoritesCount: Int
    var isFavorite: Bool
    var favoriteAction: () -> Void
    var repliesCount: Int
    var replyAction: () -> Void
    
    private let buttonsSize: CGFloat = 55
    
    @StateObject private var imageSaveHandler = ImageSaveHandler()
    
    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            
            Button {
                favoriteAction()
            } label: {
                AlignedLabel(
                    value: favoritesCount,
                    systemImage: isFavorite ? "heart.fill" : "heart",
                    imageYOffset: -2
                )
            }
            .frame(height: buttonsSize-4)
            
            SaveButton(state: imageSaveHandler.state) {
                imageSaveHandler.startSaving(fullResolutionImage!)
            }
            .frame(height: buttonsSize)
            .disabled(fullResolutionImage == nil)
            
            Button {
                share([submissionUrl])
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
            }
            .frame(height: buttonsSize)
            
            Button {
                replyAction()
            } label: {
                AlignedLabel(value: repliesCount, systemImage: "bubble.right")
            }
            .frame(height: buttonsSize-4)
            
            Spacer()
        }
        // 🫠 https://forums.developer.apple.com/forums/thread/747558
        .buttonStyle(BorderlessButtonStyle())
    }
}

@available(iOS 17, *)
#Preview(traits: .sizeThatFitsLayout) {
    Group {
        SubmissionControlsView(
            submissionUrl: OfflineFASession.default.submissionPreviews[0].url,
            fullResolutionImage: UIImage(systemName: "checkmark")?.cgImage,
            favoritesCount: 15,
            isFavorite: false,
            favoriteAction: {
                print("I like it")
            },
            repliesCount: 3,
            replyAction: {
                print("Reply")
            }
        )
        SubmissionControlsView(
            submissionUrl: OfflineFASession.default.submissionPreviews[0].url,
            fullResolutionImage: UIImage(systemName: "checkmark")?.cgImage,
            favoritesCount: 0,
            isFavorite: false,
            favoriteAction: {
                print("I like it")
            },
            repliesCount: 0,
            replyAction: {
                print("Reply")
            }
        )
    }
    .preferredColorScheme(.dark)
    .background {
        Rectangle()
            .fill(.clear)
            .border(.secondary)
            .offset(y: 3)
            .frame(height: 18)
    }
}
