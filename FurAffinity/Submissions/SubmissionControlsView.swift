//
//  SubmissionControlsView.swift
//  FurAffinity
//
//  Created by Ceylo on 27/11/2021.
//

import SwiftUI

private let buttonsSize: CGFloat = 55

struct ReplyButton: View {
    var repliesCount: Int
    var acceptsNewReplies: Bool
    var replyAction: () -> Void
    
    var body: some View {
        if acceptsNewReplies {
            Button {
                replyAction()
            } label: {
                AlignedLabel(value: repliesCount, systemImage: "bubble", imageYOffset: -1)
            }
            .frame(height: buttonsSize-4)
        } else {
            Menu {
                Text("Comment posting has been disabled")
            } label: {
                AlignedLabel(value: repliesCount, systemImage: "exclamationmark.bubble", imageYOffset: -1)
                    .foregroundStyle(.orange)
            }
            .frame(height: buttonsSize-3)
        }
    }
}

struct SubmissionControlsView: View {
    var submissionUrl: URL
    var mediaFileUrl: URL?
    var favoritesCount: Int
    var isFavorite: Bool
    var favoriteAction: () -> Void
    var repliesCount: Int
    var acceptsNewReplies: Bool
    var replyAction: () -> Void
        
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
            .sensoryFeedback(.impact, trigger: isFavorite, condition: {
                $1 == true
            })
            
            SaveButton(state: saveHandler.state) {
                Task {
                    await saveHandler.saveMedia(atFileUrl: mediaFileUrl!)
                }
            }
            .frame(height: buttonsSize)
            .disabled(mediaFileUrl == nil)
            .sensoryFeedback(.impact, trigger: saveHandler.state, condition: {
                $1 == .succeeded
            })
            
            Button {
                share([submissionUrl])
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
            }
            .frame(height: buttonsSize)
            
            ReplyButton(
                repliesCount: repliesCount,
                acceptsNewReplies: acceptsNewReplies,
                replyAction: replyAction
            )
            
            Spacer()
        }
        // 🫠 https://forums.developer.apple.com/forums/thread/747558
        .buttonStyle(BorderlessButtonStyle())
    }
}

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
            acceptsNewReplies: true,
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
            acceptsNewReplies: false,
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
