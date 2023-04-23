//
//  CommentEditor.swift
//  FurAffinity
//
//  Created by Ceylo on 22/01/2023.
//

import SwiftUI

struct CommentEditor: View {
    enum Action {
        case submit
        case cancel
    }
    
    @Binding var text: String
    var handler: (_ action: Action) -> Void
    @FocusState private var editorHasFocus: Bool
    
    var body: some View {
        VStack {
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
            TextEditor(text: $text)
                .focused($editorHasFocus)
                .onAppear {
                    editorHasFocus = true
                }
                .padding(.horizontal)
        }
    }
}

struct CommentEditor_Previews: PreviewProvider {
    static var previews: some View {
        CommentEditor(text: .constant("Hello")) { contents in
            print(contents as Any)
        }
        .border(.red)
    }
}
