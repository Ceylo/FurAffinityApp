//
//  AvatarView.swift
//  FurAffinityUI (Android)
//
//  Android counterpart of the shared `FurAffinity/Helper Views/AvatarView.swift`, which
//  is Kingfisher-only and therefore NOT symlinked here. This one matches the same public
//  surface (`init(avatarUrl:)`, `.cornerRadius`, `.fadeDuration`) but is built on the
//  Coil-backed `FAImage`.
//
//  Deferred to a later step: honoring `@Default(.animateAvatars)` with real animated-GIF
//  avatars (needs `coil-gif`), and the shared `.defaultAvatar`/`Color.borderOverlay`
//  assets. For now avatars are static with a neutral placeholder and border.
//
//  `Double` (not `CGFloat`) throughout: two CGFloat typealiases (both aka Double) are
//  visible here and lookup is ambiguous; Double is the same type and unambiguous.
//

import Foundation
import SwiftUI
import FAKit

struct AvatarView: View {
    var avatarUrl: URL?
    private var radius: Double = 5
    private var fade: Double = 0.25

    init(avatarUrl: URL? = nil) {
        self.avatarUrl = avatarUrl
    }

    func cornerRadius(_ value: Double) -> Self {
        var copy = self
        copy.radius = value
        return copy
    }

    func fadeDuration(_ value: Double) -> Self {
        var copy = self
        copy.fade = value
        return copy
    }

    var body: some View {
        FAImage(avatarUrl)
            .placeholder { Color.white.opacity(0.1) }
            .fade(duration: fade)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            }
    }
}
