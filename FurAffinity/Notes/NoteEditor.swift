//
//  CommentEditor.swift
//  FurAffinity
//
//  Created by Ceylo on 22/01/2023.
//

import SwiftUI
import FAKit
import Combine

struct NoteEditor: View {
    @ObservedObject var reply: NoteReply
    var defaultContents: NoteReplySession.DefaultContents
    var handler: (_ action: ReplyEditorAction) async -> Void
    
    @FocusState private var destinationUserHasFocus: Bool
    @FocusState private var subjectHasFocus: Bool
    @FocusState private var textEditorHasFocus: Bool
    @State private var actionInProgress: ReplyEditorAction?
    @State private var avatarUrl: URL?
    // Should not be needed but looks like
    // https://www.hackingwithswift.com/forums/100-days-of-swiftui/unusual-behavior-when-trying-to-change-the-style-of-the-text-in-a-swiftui-textfield/28414
    // is not solved…
    @State private var isUsernameValid = false
    
    var canCancel: Bool { actionInProgress == nil }
    var canSubmit: Bool {
        guard actionInProgress == nil else {
            return false
        }
        
        return reply.isValidForSubmission
    }
    
    var controls: some View {
        HStack(spacing: 10) {
            SheetButton(symbol: "xmark") {
                actionInProgress = .cancel
                Task {
                    await handler(.cancel)
                    actionInProgress = nil
                }
            }
            .applying {
                if #available(iOS 26, *) {
                    $0.buttonStyle(.glass)
                } else {
                    $0.buttonStyle(.bordered)
                }
            }
            .disabled(!canCancel)
            
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
            .applying {
                if #available(iOS 26, *) {
                    $0.buttonStyle(.glassProminent)
                } else {
                    $0.buttonStyle(.borderedProminent)
                }
            }
            .disabled(!canSubmit)
            
            if actionInProgress == .submit {
                ProgressView()
            }
        }
        .padding()
        .font(.title3)
    }
    
    var toField: some View {
        LabeledContent("To:") {
            AvatarView(avatarUrl: avatarUrl)
                .fadeDuration(0)
                .frame(width: 32, height: 32)
            TextField("static user name", text: $reply.destinationUser)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(isUsernameValid ? Color.primary : Color.red)
                .onReceive(
                    reply.$destinationUser
                        .debounce(for: 1.0, scheduler: RunLoop.main)
                ) { user in
                    guard reply.isUsernameValid else { return }
                    avatarUrl = FAURLs.avatarUrl(for: user)
                }
                .onChange(of: reply.isUsernameValid) { _, newValue in
                    isUsernameValid = newValue
                }
        }
        .focused($destinationUserHasFocus)
        .foregroundStyle(.secondary)
    }
    
    var subjectField: some View {
        LabeledContent("Subject:") {
            TextField("", text: $reply.subject)
                .foregroundStyle(.primary)
        }
        .focused($subjectHasFocus)
        .foregroundStyle(.secondary)
    }
    
    var messageField: some View {
        TextEditor(text: $reply.text)
            .autocorrectionDisabled()
            .focused($textEditorHasFocus)
            .padding()
    }
    
    func setDefaultFieldContents() {
        if reply.destinationUser.isEmpty && !defaultContents.destinationUser.isEmpty {
            reply.destinationUser = defaultContents.destinationUser
            avatarUrl = FAURLs.avatarUrl(for: defaultContents.destinationUser)
        }
        
        if reply.subject.isEmpty {
            reply.subject = defaultContents.subject
        }
        
        if reply.text.isEmpty {
            reply.text = defaultContents.text
        }
    }
    
    func chooseFocusedField() {
        if reply.destinationUser.isEmpty {
            destinationUserHasFocus = true
        } else if reply.subject.isEmpty {
            subjectHasFocus = true
        } else {
            textEditorHasFocus = true
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            controls
            
            Divider()
            
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        VStack {
                            toField
                            Divider()
                            subjectField
                        }
                        .padding()
                        
                        Divider()
                        messageField
                    }
                    .frame(minHeight: geometry.size.height)
                    .onAppear {
                        setDefaultFieldContents()
                        chooseFocusedField()
                    }
                }
            }
        }
    }
}

#Preview("New note") {
    @Previewable
    @StateObject var reply = NoteReply()
    
    NoteEditor(
        reply: reply,
        defaultContents: .init() //.init(destinationUser: "tata", subject: "titi", text: "toto")
    ) { action in
        try! await Task.sleep(for: .seconds(1))
        print(action as Any)
    }
}
