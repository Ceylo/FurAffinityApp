//
//  CommentEditor.swift
//  FurAffinity
//
//  Created by Ceylo on 22/01/2023.
//

import SwiftUI

struct CommentEditor: View {
    var submit: (_ text: String?) -> Void
    @State private var text = ""
    @FocusState private var editorHasFocus: Bool
    
    var body: some View {
        VStack {
            HStack {
                Button("Cancel") {
                    submit(nil)
                }
                Spacer()
                Button("Submit") {
                    submit(text)
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
        CommentEditor { contents in
            print(contents as Any)
        }
        .border(.red)
    }
}
