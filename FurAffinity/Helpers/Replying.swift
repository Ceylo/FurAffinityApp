//
//  Commenting.swift
//  FurAffinity
//
//  Created by Ceylo on 20/04/2023.
//

import SwiftUI
import FAKit

@MainActor
protocol ReplyStorage: ObservableObject, Sendable {
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
        replyStorage: SomeReplyStorage,
        displayData: SomeReplySession.DisplayData,
        actionHandler: @escaping (_ action: ReplyEditorAction) async -> Void
    )
}

struct Replying<SomeReplyEditor: ReplyEditor>: ViewModifier {
    @Binding var replySession: SomeReplyEditor.SomeReplySession?
    var replyAction: @MainActor (_ replySession: SomeReplyEditor.SomeReplySession, _ text: SomeReplyEditor.SomeReplyStorage) async throws -> Void
    @ObservedObject private var replyStorage = SomeReplyEditor.SomeReplyStorage()
    @State private var replySent: Bool?
    @State private var showError = false
    @State private var error: Error?
    
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
            replyStorage: replyStorage,
            displayData: replySession.displayData
        ) { action in
            do {
                if case .submit = action, replyStorage.isValidForSubmission {
                    try await replyAction(replySession, replyStorage)
                    // Preserve user data unless submitted
                    replyStorage.reset()
                    replySent = true
                }
                
                self.replySession = nil
            } catch {
                self.error = error
                showError = true
            }
        }
        .alert(
            "Oops",
            isPresented: $showError,
            presenting: error,
            actions: { _ in
                Button("Dismiss") {
                    showError = false
                    error = nil
                }
            },
            message: { error in
                Text(error.localizedDescription)
            }
        )
    }
}
