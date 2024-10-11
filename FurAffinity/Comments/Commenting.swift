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
    var replyAction: (_ parentCid: Int?, _ text: String) async -> Bool
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
            parentComment: replySession.parentComment
        ) { action in
            if case .submit = action, !commentText.isEmpty {
                let result = await replyAction(replySession.parentCid, commentText)
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
            replyAction: replyAction
        ))
    }
}
