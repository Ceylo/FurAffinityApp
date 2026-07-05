//
//  UsernameField.swift
//  FurAffinity
//
//  Created by Ceylo on 04/07/2026.
//

import SwiftUI
import FAKit

/// An avatar preview + text field for entering a static (lowercase) FA username.
/// The text turns red when the current value can't be a valid username, and the
/// avatar loads (debounced) once typing settles. Place it inside a caller-supplied
/// `LabeledContent` so each site provides its own label.
struct UsernameField: View {
    @Binding var username: String
    var placeholder: String = "static, lowercase user name"

    @State private var avatarUrl: URL?

    // Drives the text color via an independent @State flip so SwiftUI re-applies
    // the TextField's foreground style live while it's first responder.
    // https://www.hackingwithswift.com/forums/swiftui/textfield-foregroundcolor-not-updating-live/
    @State private var isValid = false

    var body: some View {
        HStack {
            AvatarView(avatarUrl: avatarUrl)
                .fadeDuration(0)
                .frame(width: 32, height: 32)
            TextField(placeholder, text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(username.isEmpty || isValid ? Color.primary : Color.red)
        }
        .onChange(of: username, initial: true) { _, newValue in
            isValid = FAUsername.isValid(newValue)
        }
        .onAppear {
            // Show a pre-filled user's avatar right away, without debouncing.
            if avatarUrl == nil, FAUsername.isValid(username) {
                avatarUrl = FAURLs.avatarUrl(for: username)
            }
        }
        .task(id: username) {
            // Debounce: only load once typing settles. The changing task id
            // auto-cancels the previous sleep on each keystroke.
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, FAUsername.isValid(username) else { return }
            avatarUrl = FAURLs.avatarUrl(for: username)
        }
    }
}

#Preview {
    @Previewable @State var username = "terriniss"
    Form {
        LabeledContent("User") {
            UsernameField(username: $username)
        }
    }
}
