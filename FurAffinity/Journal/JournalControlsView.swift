//
//  JournalControlsView.swift
//  FurAffinity
//
//  Created by Ceylo on 27/11/2021.
//

import SwiftUI
import FAKit

struct JournalControlsView: View {
    var journalUrl: URL
    var repliesCount: Int
    var acceptsNewReplies: Bool
    var replyAction: () -> Void
    
    private let buttonsSize: CGFloat = 55
    
    var body: some View {
        HStack(spacing: 0) {
            Spacer()
            
            Button {
                share([journalUrl])
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

#Preview {
    withAsync({ await FAJournal.demo }) { journal in
        Group {
            JournalControlsView(
                journalUrl: journal.url,
                repliesCount: 12,
                acceptsNewReplies: true,
                replyAction: {
                    print("Reply")
                }
            )
            
            JournalControlsView(
                journalUrl: journal.url,
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
}
