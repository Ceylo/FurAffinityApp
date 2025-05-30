//
//  CommentEditor.swift
//  FurAffinity
//
//  Created by Ceylo on 22/01/2023.
//

import SwiftUI
import FAKit

struct CommentEditor: View {
    enum Action {
        case submit
        case cancel
    }
    
    @Binding var text: String
    var parentComment: FAComment?
    var parentNote: FANote?
    var handler: (_ action: Action) async -> Void
    @FocusState private var editorHasFocus: Bool
    @State private var actionInProgress: Action?
    
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
                .disabled(text.isEmpty || actionInProgress != nil)
                
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
                        } else if let parentNote {
                            NoteContentsView(note: parentNote, showWarning: false)
                                .allowsHitTesting(false)
                                .padding([.leading, .trailing, .top])
                                .padding(.bottom, -10)
                            Divider()
                        }
                        
                        TextEditor(text: $text)
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
    withAsync({ await FAComment.demo[0] }) {
        CommentEditor(text: .constant("Hello"), parentComment: $0) { action in
            try! await Task.sleep(for: .seconds(1))
            print(action as Any)
        }
    }
}

#Preview("Reply to note") {
    withAsync({ await FANote.demo }) {
        CommentEditor(text: .constant(""), parentNote: $0) { action in
            try! await Task.sleep(for: .seconds(1))
            print(action as Any)
        }
    }
}
