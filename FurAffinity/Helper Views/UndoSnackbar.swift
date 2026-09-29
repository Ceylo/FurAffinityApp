//
//  UndoSnackbar.swift
//  FurAffinity
//
//  Created by Ceylo on 28/09/2026.
//

import SwiftUI

/// A Material snackbar offering to undo `message`. SwiftUI has no inverse-surface
/// colour, so it inverts `primary` and the background, which is what Material's
/// `inverseSurface` / `inverseOnSurface` pair amounts to.
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
                    .padding(.horizontal, 8)
                    .frame(minHeight: 48)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.background)
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(minHeight: 48)
        .background(Color.primary, in: RoundedRectangle(cornerRadius: 4))
        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
        // The margins stay inside the view, so an animated opacity doesn't clip the shadow.
        .padding(16)
    }
}

#Preview {
    VStack {
        Spacer()
        UndoSnackbar(message: "Submission deleted") {}
    }
}
