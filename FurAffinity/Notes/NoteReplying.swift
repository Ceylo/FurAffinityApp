//
//  NoteReplying.swift
//  FurAffinity
//
//  Created by Ceylo on 14/06/2025.
//

import SwiftUI
import FAKit

final class NoteReply: ObservableObject, ReplyStorage {
    var isValidForSubmission: Bool {
        !destinationUser.isEmpty && !subject.isEmpty && !text.isEmpty
    }
    
    func reset() {
        destinationUser = ""
        subject = ""
        text = ""
    }
    
    @Published var destinationUser = ""
    @Published var subject = ""
    @Published var text = ""
}

struct NoteReplySession: ReplySession {
    struct DefaultContents {
        let destinationUser: String 
        let subject: String
        let text: String
    }
    
    var displayData: DefaultContents { defaultContents }
    let defaultContents: DefaultContents
}

extension NoteReplySession.DefaultContents {
    init() {
        self.init(destinationUser: "", subject: "", text: "")
    }
}


extension NoteEditor: ReplyEditor {
    typealias SomeReplySession = NoteReplySession
    
    init(
        replyStorage: NoteReply,
        displayData: NoteReplySession.DisplayData,
        actionHandler: @escaping (_ action: ReplyEditorAction) async -> Void
    ) {
        self.init(
            reply: replyStorage,
            defaultContents: displayData,
            handler: actionHandler
        )
    }
}

typealias NoteReplying = Replying<NoteEditor>

extension View {
    func noteReplySheet(
        on replySession: Binding<NoteReplySession?>,
        _ replyAction: @MainActor @escaping (_ reply: NoteReply) async -> Bool
    ) -> some View {
        modifier(NoteReplying(
            replySession: replySession,
            replyAction: { session, reply in
                await replyAction(reply)
            }
        ))
    }
}
