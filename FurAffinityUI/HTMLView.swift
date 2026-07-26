//
//  HTMLView.swift
//  FurAffinityUI (Android)
//
//  Android counterpart of the iOS `HTMLView`. The iOS one is a `UIViewRepresentable`
//  over a manually sized `UITextView` with animated-GIF overlays; none of that exists
//  here, and none of it is needed: `Text(AttributedString)` (implemented in the
//  skip-fuse-ui fork) renders the same content and self-sizes.
//
//  `initialHeight` is accepted and ignored — it only ever seeded the iOS manual sizing.
//  FAKit's Android `AttributedString(FAHTML:)` already drops `<img>`, so there are no
//  inline avatars to animate.
//

import SwiftUI

struct HTMLView: View {
    var text: AttributedString

    init(text: AttributedString, initialHeight: CGFloat = 0) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
    }
}
