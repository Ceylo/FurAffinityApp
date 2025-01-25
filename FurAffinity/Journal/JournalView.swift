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
    
    var header: some View {
        AuthoredHeaderView(
            username: journal.author,
            displayName: journal.displayAuthor,
            title: journal.title,
            avatarUrl: FAURLs.avatarUrl(for: journal.author),
            datetime: .init(journal.datetime,
                            journal.naturalDatetime)
        )
    }
    
    var journalContents: some View {
        HTMLView(
            text: journal.description.convertingLinksForInAppNavigation(),
            initialHeight: 300
        )
    }
    
    var journalControls: some View {
        JournalControlsView(
            journalUrl: journal.url,
            repliesCount: journal.comments.recursiveCount,
            acceptsNewReplies: journal.acceptsNewComments,
            replyAction: {
                replySession = .init(parentCid: nil, among: [])
            }
        )
    }
    
    @ViewBuilder
    var journalComments: some View {
        if !journal.comments.isEmpty {
            Section {
                CommentsView(
                    comments: journal.comments,
                    highlightedCommentId: journal.targetCommentId,
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
    
    var body: some View {
        ScrollViewReader { reader in
            List {
                Group {
                    Group {
                        header
                        Divider()
                            .padding(.vertical, 5)
                        journalContents
                        journalControls
                    }
                    .padding(.horizontal, 10)
                    
                    journalComments
                }
                .listRowSeparator(.hidden)
                .listRowInsets(.init())
            }
            .commentSheet(on: $replySession, replyAction)
            .navigationTitle(journal.title)
            .navigationBarTitleDisplayMode(.inline)
            .listStyle(.plain)
            .onFirstAppear {
                prefetchAvatars(for: journal.comments)
                
                if let targetCommentId = journal.targetCommentId {
                    Task {
                        withAnimation {
                            reader.scrollTo(targetCommentId, anchor: .center)
                        }
                    }
                }
            }
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
