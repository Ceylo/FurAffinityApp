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
    var replyAction: (_ parentCid: Int?, _ text: String) -> Void
    
    @State private var replySession: Commenting.ReplySession?
    
    var body: some View {
        List {
            Group {
                Group {
                    AuthoredHeaderView(
                        username: journal.author,
                        displayName: journal.displayAuthor,
                        title: journal.title,
                        avatarUrl: journal.authorAvatarUrl,
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
    }
}

struct JournalView_Previews: PreviewProvider {
    static var previews: some View {
        JournalView(
            journal: FAJournal.demo,
            replyAction: { parentCid,text in }
        )
    }
}
