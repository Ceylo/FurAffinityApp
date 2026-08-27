//
//  AvatarView.swift
//  FurAffinity
//
//  Created by Ceylo on 09/04/2022.
//
//  `Double`, not `CGFloat`: two CGFloat typealiases (both aka Double) are visible on
//  Android and the bare name is ambiguous as a type annotation. SE-0307's implicit
//  conversion keeps the iOS call sites unchanged.
//

import Foundation
import SwiftUI
import FAKit
import Defaults
#if canImport(Kingfisher)
import Kingfisher
#endif

struct AvatarView: View {
    var avatarUrl: URL?
    // Internal, not private: bridged state (Android/docs/shared-sources.md).
    @Default(.animateAvatars) var animateAvatars
    private var cornerRadius: Double = 5
    private var fadeDuration = 0.25

    init(avatarUrl: URL? = nil) {
        self.avatarUrl = avatarUrl
    }

    func cornerRadius(_ radius: Double) -> Self {
        var copy = self
        copy.cornerRadius = radius
        return copy
    }

    func fadeDuration(_ duration: Double) -> Self {
        var copy = self
        copy.fadeDuration = duration
        return copy
    }

    private var loadingPlaceholder: some View {
        Color.white.opacity(0.1)
    }

    private var failureImage: some View {
        Image("DefaultAvatar", bundle: Bundle.faAssets)
            .resizable()
    }

    // Only `configure`'s signature differs by platform, but Swift wants whole
    // declarations in an `#if` arm, so the chain is spelled twice.
#if canImport(Kingfisher)
    private func configure(_ image: some KFImageProtocol) -> some KFImageProtocol {
        image
            .placeholder { loadingPlaceholder }
            .onFailureView { failureImage }
            .fade(duration: fadeDuration)
    }
#else
    /// Animated GIF avatars are a deferred follow-up (needs coil-gif), so
    /// `animateAvatars` is read but not honored here — see Android/docs/images.md.
    private func configure(_ image: FAImageView) -> FAImageView {
        image
            .placeholder { loadingPlaceholder }
            .onFailureView { failureImage }
            .fade(duration: fadeDuration)
    }
#endif

    var body: some View {
        ZStack {
#if canImport(Kingfisher)
            if animateAvatars {
                configure(FAAnimatedImage(avatarUrl))
            } else {
                configure(FAImage(avatarUrl))
            }
#else
            configure(FAImage(avatarUrl))
#endif
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.borderOverlay, lineWidth: 1)
        }
    }
}

#if !FA_SKIP_MODULE
#Preview("With URL", traits: .sizeThatFitsLayout) {
    AvatarView(avatarUrl: URL(string: "https://a.furaffinity.net/terriniss.gif")!)
        .frame(width: 32, height: 32)
        .padding()
        .preferredColorScheme(.dark)
}

#Preview("Empty", traits: .sizeThatFitsLayout) {
    AvatarView(avatarUrl: nil)
        .frame(width: 32, height: 32)
        .padding()
        .preferredColorScheme(.dark)
}
#endif
