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
    
    struct ReplySession {
        let parentCid: Int?
    }
    @State private var replySession: ReplySession?
    
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
        .sheet(isPresented: showCommentEditor) {
            commentEditor
        }
        .navigationTitle(journal.title)
    }
}

// MARK: - Comment replies
// TODO: Factorize with SubmissionView
extension JournalView {
    var showCommentEditor: Binding<Bool> {
        .init {
            replySession != nil
        } set: { value in
            if value {
                fatalError()
            } else {
                replySession = nil
            }
        }
    }
    
    private var commentEditor: some View {
        guard let replySession else {
            fatalError()
        }
        
        return CommentEditor { text in
            if let text {
                replyAction(replySession.parentCid, text)
            }
            self.replySession = nil
        }
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
