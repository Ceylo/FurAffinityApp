//
//  JournalView.swift
//  FurAffinity
//
//  Created by Ceylo on 30/03/2023.
//

import SwiftUI
import FAKit

struct JournalView: View {
    var journal: FAJournal
    var description: AttributedString?
    var replyAction: (_ parentCid: Int?, _ text: String) -> Void
    
    @State private var replySession: Commenting.ReplySession?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView(
                username: journal.author,
                displayName: journal.displayAuthor,
                title: journal.title,
                avatarUrl: journal.authorAvatarUrl,
                datetime: .init(journal.datetime,
                                journal.naturalDatetime)
            )
            Divider()
                .padding(.vertical, 5)

            if let description {
                TextView(text: description, initialHeight: 300)
            }
            
            JournalControlsView(
                journalUrl: journal.url,
                replyAction: {
                    replySession = .init(parentCid: nil)
                }
            )
            .padding(.bottom, 10)
            
            CommentsView(
                comments: journal.comments,
                replyAction: { cid in
                    replySession = .init(parentCid: cid)
                }
            )
        }
        .padding(10)
        .commentSheet(on: $replySession, replyAction)
        .navigationTitle(journal.title)
    }
}

struct JournalView_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            JournalView(
                journal: FAJournal.demo,
                description: AttributedString(FAHTML: FAJournal.demo.htmlDescription)?
                    .convertingLinksForInAppNavigation(),
                replyAction: { parentCid,text in }
            )
        }
    }
}
