//
//  JournalView.swift
//  FurAffinity
//
//  Created by Ceylo on 30/03/2023.
//

import SwiftUI
import FAKit
import Combine

struct JournalView: View {
    var journal: FAJournal
    var replyAction: (_ parentCid: Int?, _ text: String) async -> Bool
    
    @State private var replySession: Commenting.ReplySession?
    
    var body: some View {
        List {
            Group {
                Group {
                    AuthoredHeaderView(
                        username: journal.author,
                        displayName: journal.displayAuthor,
                        title: journal.title,
                        avatarUrl: FAURLs.avatarUrl(for: journal.author),
                        datetime: .init(journal.datetime,
                                        journal.naturalDatetime)
                    )
                    Divider()
                        .padding(.vertical, 5)
                    
                    HTMLView(
                        text: journal.description.convertingLinksForInAppNavigation(),
                        initialHeight: 300
                    )
                    
                    JournalControlsView(
                        journalUrl: journal.url,
                        repliesCount: journal.comments.recursiveCount,
                        acceptsNewReplies: journal.acceptsNewComments,
                        replyAction: {
                            replySession = .init(parentCid: nil, among: [])
                        }
                    )
                }
                .padding(.horizontal, 10)
                
                if !journal.comments.isEmpty {
                    Section {
                        CommentsView(
                            comments: journal.comments,
                            acceptsNewReplies: journal.acceptsNewComments,
                            replyAction: { cid in
                                replySession = .init(parentCid: cid, among: journal.comments)
                            }
                        )
                    } header: {
                        SectionHeader(text: "Comments")
                    }
                }
            }
            .listRowSeparator(.hidden)
            .listRowInsets(.init())
        }
        .commentSheet(on: $replySession, replyAction)
        .navigationTitle(journal.title)
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.plain)
        .onAppear {
            prefetchAvatars(for: journal.comments)
        }
    }
}

#Preview {
    withAsync({ await FAJournal.demo }) {
        JournalView(
            journal: $0,
            replyAction: { _, _ in true }
        )
    }
}
