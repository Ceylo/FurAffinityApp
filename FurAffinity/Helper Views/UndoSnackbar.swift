//
//  UndoSnackbar.swift
//  FurAffinity
//
//  Created by Ceylo on 28/09/2026.
//

import SwiftUI

/// A Material snackbar offering to undo `message`.
struct UndoSnackbar: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(message)
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button {
                onUndo()
            } label: {
                Text("Undo")
                    .font(.subheadline)
                    .bold()
                    .foregroundStyle(Self.actionColor)
                    .padding(.horizontal, 8)
                    .frame(minHeight: 48)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Self.contentColor)
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(minHeight: 48)
        .background(Self.containerColor, in: RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
        // The margins stay inside the view, so an animated opacity doesn't clip the shadow.
        .padding(16)
    }

    #if os(Android) // SkipSwiftUI API, absent from the host build of this module
    private static let containerColor = Color.material(.inverseSurface)
    private static let contentColor = Color.material(.inverseOnSurface)
    private static let actionColor = Color.material(.inversePrimary)
    #else
    private static let containerColor = Color.primary
    private static let contentColor = Color(.systemBackground)
    private static let actionColor = contentColor
    #endif
}

#Preview {
    VStack {
        Spacer()
        UndoSnackbar(message: "Submission deleted") {}
    }
}
