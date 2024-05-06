//
//  JournalView.swift
//  FurAffinity
//
//  Created by Ceylo on 30/03/2023.
//

import SwiftUI
import FAKit
import Combine

struct JournalViewModel {
    var journal: FAJournal
    var attributedDescription: AttributedString
}

extension JournalViewModel {
    init(_ journal: FAJournal) {
        let description = AttributedString(FAHTML: journal.htmlDescription)?
            .convertingLinksForInAppNavigation()
        self.init(journal: journal, attributedDescription: description ?? "Failed loading contents")
    }
}

struct JournalView: View {
    var journal: JournalViewModel
    var replyAction: (_ parentCid: Int?, _ text: String) -> Void
    
    private var faJournal: FAJournal { journal.journal }
    @State private var replySession: Commenting.ReplySession?
    
    var body: some View {
        List {
            Group {
                Group {
                    AuthoredHeaderView(
                        username: faJournal.author,
                        displayName: faJournal.displayAuthor,
                        title: faJournal.title,
                        avatarUrl: faJournal.authorAvatarUrl,
                        datetime: .init(faJournal.datetime,
                                        faJournal.naturalDatetime)
                    )
                    Divider()
                        .padding(.vertical, 5)
                    
                    HTMLView(text: journal.attributedDescription, initialHeight: 300)
                    
                    JournalControlsView(
                        journalUrl: faJournal.url,
                        replyAction: {
                            replySession = .init(parentCid: nil, among: [])
                        }
                    )
                }
                .padding(.horizontal, 10)
                
                if !faJournal.comments.isEmpty {
                    Section {
                        CommentsView(
                            comments: faJournal.comments,
                            replyAction: { cid in
                                replySession = .init(parentCid: cid, among: faJournal.comments)
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
        .navigationTitle(faJournal.title)
        .listStyle(.plain)
    }
}

struct JournalView_Previews: PreviewProvider {
    static var previews: some View {
        JournalView(
            journal: JournalViewModel(FAJournal.demo),
            replyAction: { parentCid,text in }
        )
    }
}
