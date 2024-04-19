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
        VStack(alignment: .leading, spacing: 0) {
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

            TextView(text: journal.attributedDescription, initialHeight: 300)
            
            JournalControlsView(
                journalUrl: faJournal.url,
                replyAction: {
                    replySession = .init(parentCid: nil, among: [])
                }
            )
            .padding(.bottom, 10)
            
            if !faJournal.comments.isEmpty {
                VStack {
                    Text("Comments")
                        .font(.headline)
                    CommentsView(
                        comments: faJournal.comments,
                        replyAction: { cid in
                            replySession = .init(parentCid: cid, among: faJournal.comments)
                        }
                    )
                }
            }
        }
        .padding(10)
        .commentSheet(on: $replySession, replyAction)
        .navigationTitle(faJournal.title)
    }
}

struct JournalView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            JournalView(
                journal: JournalViewModel(FAJournal.demo),
                replyAction: { parentCid,text in }
            )
        }
    }
}
