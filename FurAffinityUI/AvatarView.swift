//
//  AvatarView.swift
//  FurAffinityUI (Android)
//
//  Android counterpart of the shared `FurAffinity/Helper Views/AvatarView.swift`, which
//  is Kingfisher-only and therefore NOT symlinked here. This one matches the same public
//  surface (`init(avatarUrl:)`, `.cornerRadius`, `.fadeDuration`) but is built on the
//  Coil-backed `FAImage`.
//
//  The default-avatar image and the border color come from this module's own
//  Assets.xcassets, which Skip mirrors into Android resources: `DefaultAvatar` is a PNG
//  rendition of the iOS `.heic` (which Android can't decode) and `BorderOverlay.colorset`
//  is a symlink to the iOS one, so the border matches on both platforms.
//
//  Deferred to a later step: honoring `@Default(.animateAvatars)` with real animated-GIF
//  avatars (needs `coil-gif`).
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
            .onFailureView {
                Image("DefaultAvatar", bundle: .module)
                    .resizable()
            }
            .fade(duration: fade)
            .clipShape(RoundedRectangle(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .stroke(Color.borderOverlay, lineWidth: 1)
            }
    }
}

extension Color {
    /// The shared `BorderOverlay` colorset (black @0.1 light / white @0.2 dark).
    static let borderOverlay = Color("BorderOverlay", bundle: .module)
}
