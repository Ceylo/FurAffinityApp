//
//  SubmissionControlsView.swift
//  FurAffinity
//
//  Created by Ceylo on 27/11/2021.
//

import SwiftUI

private let buttonsSize: CGFloat = 55

extension Color {
    static let buttonTint: Color = {
        if #available(iOS 26, *) {
            Color.primary
        } else {
            Color.accentColor
        }
    }()
}

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
                    .tint(Color.buttonTint)
            }
            .frame(height: buttonsSize-4)
        } else {
            Menu {
                Text("Comment posting has been disabled")
            } label: {
                AlignedLabel(value: repliesCount, systemImage: "exclamationmark.bubble", imageYOffset: -1)
                    .tint(.orange)
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
    var metadataTarget: FATarget?
    
    @StateObject private var saveHandler = MediaSaveHandler()
    
    var body: some View {
        HStack {
            Spacer()
            HStack(spacing: 0) {
                Button {
                    favoriteAction()
                } label: {
                    AlignedLabel(
                        value: favoritesCount,
                        systemImage: isFavorite ? "heart.fill" : "heart",
                        imageYOffset: -2
                    )
                    .tint(Color.buttonTint)
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
                
                ReplyButton(
                    repliesCount: repliesCount,
                    acceptsNewReplies: acceptsNewReplies,
                    replyAction: replyAction
                )
            }
            .applying {
                if #available(iOS 26, *) {
                    $0.offset(y: -3)
                        .padding(-5)
                        .glassEffect(.regular.interactive())
                } else { $0 }
            }
            
            FALink(destination: metadataTarget) {
                Image(systemName: "text.badge.star")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding()
                    .offset(y: 2)
                    .foregroundStyle(Color.buttonTint)
            }
            .frame(height: buttonsSize)
            .applying {
                if #available(iOS 26, *) {
                    $0.offset(y: -3)
                        .padding(-5)
                        .glassEffect(.regular.interactive())
                } else { $0 }
            }
            
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
            },
            metadataTarget: nil
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
            },
            metadataTarget: nil
        )
    }
    .preferredColorScheme(.dark)
    .overlay {
        Rectangle()
            .fill(.clear)
            .border(.secondary)
            .applying {
                if #available(iOS 26, *) {
                    $0
                } else {
                    $0.offset(y: 3)
                }
            }
            .frame(height: 18)
    }
}
