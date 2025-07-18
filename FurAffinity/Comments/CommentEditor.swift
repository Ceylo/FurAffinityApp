//
//  CommentEditor.swift
//  FurAffinity
//
//  Created by Ceylo on 22/01/2023.
//

import SwiftUI
import FAKit

struct SheetButton: View {
    var symbol: String
    var action: () -> Void
    var size: Double = 16
    
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .tint(.blue)
                .frame(width: size, height: size)
                .padding(2)
        }
        .buttonBorderShape(.circle)
    }
}

struct CommentEditor: View {
    @ObservedObject var reply: CommentReply
    var parentComment: FAComment?
    var handler: (_ action: ReplyEditorAction) async -> Void
    @FocusState private var editorHasFocus: Bool
    @State private var actionInProgress: ReplyEditorAction?
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                SheetButton(symbol: "xmark") {
                    actionInProgress = .cancel
                    Task {
                        await handler(.cancel)
                        actionInProgress = nil
                    }
                }
                .buttonStyle(.glass)
                .disabled(actionInProgress != nil)
                
                if actionInProgress == .cancel {
                    ProgressView()
                }
                
                Spacer()
                SheetButton(symbol: "arrow.up") {
                    actionInProgress = .submit
                    Task {
                        await handler(.submit)
                        actionInProgress = nil
                    }
                }
                .buttonStyle(.glassProminent)
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
