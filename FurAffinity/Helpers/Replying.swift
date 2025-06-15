//
//  Commenting.swift
//  FurAffinity
//
//  Created by Ceylo on 20/04/2023.
//

import SwiftUI
import FAKit

protocol ReplyStorage: ObservableObject {
    init()
    var isValidForSubmission: Bool { get }
    func reset()
}

protocol ReplySession: Sendable {
    associatedtype DisplayData
    var displayData: DisplayData { get }
}

enum ReplyEditorAction {
    case submit
    case cancel
}

protocol ReplyEditor<SomeReplyStorage>: View {
    associatedtype SomeReplyStorage: ReplyStorage
    associatedtype SomeReplySession: ReplySession
    
    init(
        replyStorage: ObservedObject<SomeReplyStorage>,
        displayData: SomeReplySession.DisplayData,
        actionHandler: @escaping (_ action: ReplyEditorAction) async -> Void
    )
}

struct Replying<SomeReplyEditor: ReplyEditor>: ViewModifier {
    @Binding var replySession: SomeReplyEditor.SomeReplySession?
    var replyAction: @MainActor (_ replySession: SomeReplyEditor.SomeReplySession, _ text: SomeReplyEditor.SomeReplyStorage) async -> Bool
    @ObservedObject private var replyStorage = SomeReplyEditor.SomeReplyStorage()
    @State private var replySent: Bool?
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: showReplyEditor) {
                replyEditor
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
    
    private var showReplyEditor: Binding<Bool> {
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
    
    private var replyEditor: some View {
        guard let replySession else {
            fatalError()
        }
        
        return SomeReplyEditor(
            replyStorage: _replyStorage,
            displayData: replySession.displayData
        ) { action in
            if case .submit = action, replyStorage.isValidForSubmission {
                let result = await replyAction(replySession, replyStorage)
                // Preserve user data unless submitted
                replyStorage.reset()
                replySent = result
            }
            
            self.replySession = nil
        }
    }
}
