//
//  Commenting.swift
//  FurAffinity
//
//  Created by Ceylo on 20/04/2023.
//

import Foundation
import SwiftUI
import FAKit

struct Commenting: ViewModifier {
    struct ReplySession {
        let parentCid: Int?
        let parentComment: FAComment?
        let parentNote: FANote?
        
        init(parentCid: Int?, among comments: [FAComment]) {
            self.parentCid = parentCid
            self.parentComment = parentCid.flatMap { cid in
                comments.recursiveFirst { $0.cid == cid }
            }
            self.parentNote = nil
        }
        
        init(parentNote: FANote) {
            self.parentCid = nil
            self.parentComment = nil
            self.parentNote = parentNote
        }
    }

    @Binding var replySession: ReplySession?
    var replyAction: (_ replySession: ReplySession, _ text: String) async -> Bool
    @State private var commentText: String = ""
    @State private var replySent: Bool?
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: showCommentEditor) {
                commentEditor
            }
            .sensoryFeedback(.success, trigger: replySent, condition: {
                $1 == true
            })
            .sensoryFeedback(.error, trigger: replySent, condition: {
                $1 == false
            })
            .onChange(of: replySent) {
                replySent = nil
            }
    }
    
    private var showCommentEditor: Binding<Bool> {
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
        
        return CommentEditor(
            text: $commentText,
            parentComment: replySession.parentComment,
            parentNote: replySession.parentNote
        ) { action in
            if case .submit = action, !commentText.isEmpty {
                let result = await replyAction(replySession, commentText)
                // Preserve user text unless submitted
                commentText = ""
                replySent = result
            }
            
            self.replySession = nil
        }
    }
}

extension View {
    func commentSheet(
        on replySession: Binding<Commenting.ReplySession?>,
        _ replyAction: @escaping (_ parentCid: Int?, _ text: String) async -> Bool
    ) -> some View {
        modifier(Commenting(
            replySession: replySession,
            replyAction: { session, text in
                await replyAction(session.parentCid, text)
            }
        ))
    }
    
    func noteReplySheet(
        on replySession: Binding<Commenting.ReplySession?>,
        _ replyAction: @escaping (_ note: FANote?, _ text: String) async -> Bool
    ) -> some View {
        modifier(Commenting(
            replySession: replySession,
            replyAction: { session, text in
                await replyAction(session.parentNote, text)
            }
        ))
    }
}
