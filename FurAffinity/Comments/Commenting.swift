//
//  Commenting.swift
//  FurAffinity
//
//  Created by Ceylo on 20/04/2023.
//

import Foundation
import SwiftUI
import FAKit

final class CommentReply: ObservableObject, ReplyStorage {
    var isValidForSubmission: Bool {
        !commentText.isEmpty
    }
    
    func reset() {
        commentText = ""
    }
    
    @Published var commentText: String = ""
}

struct CommentReplySession: ReplySession {
    var displayData: FAComment? { parentComment }
    
    let parentCid: Int?
    let parentComment: FAComment?
    
    init(parentCid: Int?, among comments: [FAComment]) {
        self.parentCid = parentCid
        self.parentComment = parentCid.flatMap { cid in
            comments.recursiveFirst { $0.cid == cid }
        }
    }
}

extension CommentEditor: ReplyEditor {
    typealias SomeReplyStorage = CommentReply
    typealias SomeReplySession = CommentReplySession
    
    init(
        replyStorage: ObservedObject<CommentReply>,
        displayData: CommentReplySession.DisplayData,
        actionHandler: @escaping (_ action: ReplyEditorAction) async -> Void
    ) {
        self.init(
            text: replyStorage.projectedValue.commentText,
            parentComment: displayData,
            handler: actionHandler
        )
    }
}

typealias Commenting = Replying<CommentEditor>

extension View {
    func commentSheet(
        on replySession: Binding<CommentReplySession?>,
        _ replyAction: @MainActor @escaping (_ parentCid: Int?, _ reply: CommentReply) async -> Bool
    ) -> some View {
        modifier(Commenting(
            replySession: replySession,
            replyAction: { session, reply in
                await replyAction(session.parentCid, reply)
            }
        ))
    }
}
