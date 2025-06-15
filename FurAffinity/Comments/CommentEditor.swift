//
//  CommentEditor.swift
//  FurAffinity
//
//  Created by Ceylo on 22/01/2023.
//

import SwiftUI
import FAKit

struct CommentEditor: View {
    @ObservedObject var reply: CommentReply
    var parentComment: FAComment?
    var handler: (_ action: ReplyEditorAction) async -> Void
    @FocusState private var editorHasFocus: Bool
    @State private var actionInProgress: ReplyEditorAction?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button("Cancel") {
                    actionInProgress = .cancel
                    Task {
                        await handler(.cancel)
                        actionInProgress = nil
                    }
                }
                .disabled(actionInProgress != nil)
                
                if actionInProgress == .cancel {
                    ProgressView()
                }
                
                Spacer()
                Button("Submit") {
                    actionInProgress = .submit
                    Task {
                        await handler(.submit)
                        actionInProgress = nil
                    }
                }
                .disabled(!reply.isValidForSubmission || actionInProgress != nil)
                
                if actionInProgress == .submit {
                    ProgressView()
                }
            }
            .padding()
            .font(.title3)
            
            Divider()
            
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        if let parentComment {
                            CommentView(comment: parentComment, highlight: false)
                                .allowsHitTesting(false)
                                .padding()
                            Divider()
                        }
                        
                        TextEditor(text: $reply.commentText)
                            .focused($editorHasFocus)
                            .onAppear {
                                editorHasFocus = true
                            }
                            .padding()
                    }
                    .frame(minHeight: geometry.size.height)
                }
            }
        }
    }
}

#Preview("Reply to journal/submission") {
    @Previewable
    @ObservedObject var reply = CommentReply()
    
    withAsync({ await FAComment.demo[0] }) {
        CommentEditor(reply: reply, parentComment: $0) { action in
            try! await Task.sleep(for: .seconds(1))
            print(action as Any)
        }
    }
}
