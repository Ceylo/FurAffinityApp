//
//  CommentEditor.swift
//  FurAffinity
//
//  Created by Ceylo on 22/01/2023.
//

import SwiftUI
import FAKit

struct NoteEditor: View {
    @Binding var destinationUser: String
    @Binding var subject: String
    @Binding var text: String
    var defaultContents: NoteReplySession.DefaultContents
    var handler: (_ action: ReplyEditorAction) async -> Void
    
    @FocusState private var destinationUserHasFocus: Bool
    @FocusState private var subjectHasFocus: Bool
    @FocusState private var textEditorHasFocus: Bool
    @State private var actionInProgress: ReplyEditorAction?
    
    var canCancel: Bool { actionInProgress == nil }
    var canSubmit: Bool {
        guard actionInProgress == nil else {
            return false
        }
        
        return !destinationUser.isEmpty && !subject.isEmpty && !text.isEmpty
    }
    
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
                .disabled(!canCancel)
                
                if actionInProgress == .cancel {
                    ProgressView()
                }
                
                Spacer()
                Button("Send Note") {
                    actionInProgress = .submit
                    Task {
                        await handler(.submit)
                        actionInProgress = nil
                    }
                }
                .disabled(!canSubmit)
                
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
                        VStack {
                            LabeledContent("To:") {
                                TextField("user static name", text: $destinationUser)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .foregroundStyle(.primary)
                            }
                            .focused($destinationUserHasFocus)
                            .foregroundStyle(.secondary)
                            
                            Divider()
                            LabeledContent("Subject:") {
                                TextField("Note title", text: $subject)
                                    .foregroundStyle(.primary)
                            }
                            .focused($subjectHasFocus)
                            .foregroundStyle(.secondary)
                        }
                        .padding()
                        
                        Divider()
                        
                        TextEditor(text: $text)
                            .autocorrectionDisabled()
                            .focused($textEditorHasFocus)
                            .padding()
                    }
                    .frame(minHeight: geometry.size.height)
                    .onAppear {
                        if destinationUser.isEmpty {
                            destinationUser = defaultContents.destinationUser
                        }
                        
                        if subject.isEmpty {
                            subject = defaultContents.subject
                        }
                        
                        if text.isEmpty {
                            text = defaultContents.text
                        }
                        
                        if destinationUser.isEmpty {
                            destinationUserHasFocus = true
                        } else if subject.isEmpty {
                            subjectHasFocus = true
                        } else {
                            textEditorHasFocus = true
                        }
                    }
                }
            }
        }
    }
}

#Preview("New note") {
    @Previewable @State var destinationUser: String = ""
    @Previewable @State var subject: String = ""
    @Previewable @State var text: String = ""
    
    NoteEditor(
        destinationUser: $destinationUser,
        subject: $subject,
        text: $text,
        defaultContents: .init() //.init(destinationUser: "tata", subject: "titi", text: "toto")
    ) { action in
        try! await Task.sleep(for: .seconds(1))
        print(action as Any)
    }
}
