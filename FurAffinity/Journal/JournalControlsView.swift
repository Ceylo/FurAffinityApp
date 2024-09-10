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

#Preview {
    withAsync({ await FAJournal.demo }) { journal in
        Group {
            JournalControlsView(journalUrl: journal.url,
                                repliesCount: 12,
                                replyAction: {
                print("Reply")
            })
            
            JournalControlsView(journalUrl: journal.url,
                                repliesCount: 0,
                                replyAction: {
                print("Reply")
            })
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
