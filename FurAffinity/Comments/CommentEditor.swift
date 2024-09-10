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
    var handler: (_ action: Action) -> Void
    @FocusState private var editorHasFocus: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") {
                    handler(.cancel)
                }
                Spacer()
                Button("Submit") {
                    handler(.submit)
                }
                .disabled(text.isEmpty)
            }
            .padding()
            .font(.title3)
            
            Divider()
            
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        if let parentComment {
                            CommentView(comment: parentComment)
                                .allowsHitTesting(false)
                                .padding()
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

#Preview {
    withAsync({ await FAComment.demo[0] }) {
        CommentEditor(text: .constant("Hello"), parentComment: $0) { contents in
            print(contents as Any)
        }
        .border(.red)
    }
}
