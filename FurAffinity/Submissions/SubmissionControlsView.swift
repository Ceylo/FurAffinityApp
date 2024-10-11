//
//  SubmissionControlsView.swift
//  FurAffinity
//
//  Created by Ceylo on 27/11/2021.
//

import SwiftUI

struct SubmissionControlsView: View {
    var submissionUrl: URL
    var mediaFileUrl: URL?
    var favoritesCount: Int
    var isFavorite: Bool
    var favoriteAction: () -> Void
    var repliesCount: Int
    var replyAction: () -> Void
    
    private let buttonsSize: CGFloat = 55
    
    @StateObject private var saveHandler = MediaSaveHandler()
    
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
            .apply {
                if #available(iOS 17, *) {
                    $0.sensoryFeedback(
                        .impact,
                        trigger: isFavorite,
                        condition: { $1 == true }
                    )
                } else { $0 }
            }
            
            SaveButton(state: saveHandler.state) {
                Task {
                    await saveHandler.saveMedia(atFileUrl: mediaFileUrl!)
                }
            }
            .frame(height: buttonsSize)
            .disabled(mediaFileUrl == nil)
            .apply {
                if #available(iOS 17, *) {
                    $0.sensoryFeedback(
                        .impact,
                        trigger: saveHandler.state,
                        condition: { $1 == .succeeded }
                    )
                } else { $0 }
            }
            
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
            mediaFileUrl: URL(fileURLWithPath: "/tmp/dummy.jpg"),
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
            mediaFileUrl: URL(fileURLWithPath: "/tmp/dummy.jpg"),
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
