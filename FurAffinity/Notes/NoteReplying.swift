//
//  NoteReplying.swift
//  FurAffinity
//
//  Created by Ceylo on 14/06/2025.
//

import SwiftUI
import FAKit

final class NoteReply: ObservableObject, ReplyStorage {
    static let allowedCharset = CharacterSet
        .lowercaseLetters
        .union(.decimalDigits)
        .union(.init(charactersIn: "^~`."))

    var isValidForSubmission: Bool {
        isUsernameValid && !subject.isEmpty && !text.isEmpty
    }
    
    var isUsernameValid: Bool {
        guard !destinationUser.isEmpty else {
            return false
        }
        
        let actualCharset = CharacterSet(charactersIn: destinationUser)
        return Self.allowedCharset.isSuperset(of: actualCharset)
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
        
        init(
            destinationUser: String = "",
            subject: String = "",
            text: String = ""
        ) {
            self.destinationUser = destinationUser
            self.subject = subject
            self.text = text
        }
    }
    
    var displayData: DefaultContents { defaultContents }
    let defaultContents: DefaultContents
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
        _ replyAction: @MainActor @escaping (_ reply: NoteReply) async throws -> Void
    ) -> some View {
        modifier(NoteReplying(
            replySession: replySession,
            replyAction: { session, reply in
                try await replyAction(reply)
            }
        ))
    }
}
