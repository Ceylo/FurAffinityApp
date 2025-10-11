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
    var replyAction: @MainActor (_ parentCid: Int?, _ reply: CommentReply) async throws -> Void
    
    @State private var replySession: CommentReplySession?
    
    var header: some View {
        TitleAuthorHeader(
            username: journal.author,
            displayName: journal.displayAuthor,
            title: journal.title,
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
        List {
            Group {
                // VStack is a workaround for broken divider on iOS 26
                VStack {
                    header
                    Divider()
                        .padding(.bottom, 5)
                }
                
                journalContents
                journalControls
                journalComments
                    .padding(.horizontal, -10)
            }
            .listRowSeparator(.hidden)
            .listRowInsets(.init())
            .padding(.horizontal, 10)
        }
        .commentSheet(on: $replySession, replyAction)
        .navigationTitle(journal.title)
        .listStyle(.plain)
        .onAppear {
            prefetchAvatars(for: journal.comments)
        }
        .scrollToItem(id: journal.targetCommentId)
    }
}

#Preview {
    withAsync({ await FAJournal.demo }) {
        JournalView(
            journal: $0,
            replyAction: { _, _ in }
        )
    }
}
