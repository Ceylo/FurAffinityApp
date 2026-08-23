//
//  AppIcon.swift
//  FurAffinityUI (Android)
//
//  Android counterpart of `FurAffinity/Helper Views/AppIcon.swift`, which can't be
//  symlinked because `Bundle.module` doesn't exist in an Xcode app target — the same
//  reason AvatarView is a substitute rather than a symlink.
//
//  The imageset is a downscaled rendition of the iOS art, generated (never committed)
//  by Scripts/Android/generate-assets.sh.
//

import SwiftUI

struct AppIcon: View {
    var body: some View {
        Image("AppIcon", bundle: .module)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 100)
    }
}
