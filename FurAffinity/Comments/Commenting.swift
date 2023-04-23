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
        
        init(parentCid: Int?, among comments: [FAComment]) {
            self.parentCid = parentCid
            self.parentComment = parentCid.flatMap { cid in
                comments.recursiveFirst { $0.cid == cid }
            }
        }
    }

    @Binding var replySession: ReplySession?
    var replyAction: (_ parentCid: Int?, _ text: String) -> Void
    @State private var commentText: String = ""
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: showCommentEditor) {
                commentEditor
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
            parentComment: replySession.parentComment
        ) { action in
            if case .submit = action, !commentText.isEmpty {
                replyAction(replySession.parentCid, commentText)
                // Preserve user text unless submitted
                commentText = ""
            }
            
            self.replySession = nil
        }
    }
}

extension View {
    func commentSheet(
        on replySession: Binding<Commenting.ReplySession?>,
        _ replyAction: @escaping (_ parentCid: Int?, _ text: String) -> Void
    ) -> some View {
        modifier(Commenting(
            replySession: replySession,
            replyAction: replyAction
        ))
    }
}
