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
import Kingfisher

struct AvatarView: View {
    var avatarUrl: URL?
    @Default(.animateAvatars) private var animateAvatars: Bool
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

    private func configure(_ image: some KFImageProtocol) -> some KFImageProtocol {
        image
            .placeholder { loadingPlaceholder }
            .onFailureView { failureImage }
            .fade(duration: fadeDuration)
    }

    var body: some View {
        ZStack {
            // On Android both arms are the same static view — `FAAnimatedImage` is
            // `FAImage` there — so the toggle has no effect until an animated decode
            // path exists.
            if animateAvatars {
                configure(FAAnimatedImage(avatarUrl))
            } else {
                configure(FAImage(avatarUrl))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.borderOverlay, lineWidth: 1)
        }
    }
}

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
