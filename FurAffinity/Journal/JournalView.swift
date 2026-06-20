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
    var sendNoteAction: (_ destinationUser: String, _ subject: String, _ text: String) async throws -> Void
    
    @State private var replySession: CommentReplySession?
    @State private var noteReplySession: NoteReplySession?
    @State private var commentsWidth: CGFloat = 0
    @State private var autoFocus: CommentFocusTarget?
    @State private var didAutoFocus = false
    @ScaledMetric private var minContentWidth: CGFloat = 220
    
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
                        .padding(.bottom, 10)
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
        .measuringCommentsAvailableWidth($commentsWidth)
        .onChange(of: commentsWidth) { _, w in
            guard !didAutoFocus, w > 0 else { return }
            let cutoff = commentInlineCutoff(availableWidth: w, minContentWidth: minContentWidth)
            if let focus = deepHighlightFocus(in: journal.comments,
                                              targetCid: journal.targetCommentId, cutoff: cutoff) {
                didAutoFocus = true
                autoFocus = focus
            }
        }
        .navigationDestination(item: $autoFocus) { focus in
            FocusedCommentsView(
                threadRoot: focus.threadRoot,
                focusedCid: focus.focusedCid,
                acceptsNewReplies: journal.acceptsNewComments,
                highlightedCommentId: journal.targetCommentId,
                replyAction: { cid in
                    replySession = .init(parentCid: cid, among: journal.comments)
                }
            )
        }
        .onAppear {
            prefetchAvatars(for: journal.comments)
        }
        .scrollToItem(id: journal.targetCommentId)
        .toolbar {
            RemoteContentToolbarItem(url: journal.url) {
                Button {
                    replySession = .init(parentCid: nil, among: [])
                } label: {
                    Label("Comment", systemImage: "bubble")
                }
                .disabled(!journal.acceptsNewComments)
                
                Button {
                    noteReplySession = .init(defaultContents: .init(
                        destinationUser: journal.author
                    ))
                } label: {
                    Label("Send a Note", systemImage: "message")
                }
            }
        }
        .noteReplySheet(on: $noteReplySession) { reply in
            try await sendNoteAction(reply.destinationUser, reply.subject, reply.text)
        }
    }
}

#Preview {
    withAsync({ await FAJournal.demo }) {
        JournalView(
            journal: $0,
            replyAction: { _, _ in },
            sendNoteAction: { _, _, _ in }
        )
    }
}
