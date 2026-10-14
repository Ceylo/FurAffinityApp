//
//  AppIcon.swift
//  FurAffinity
//
//  Created by Ceylo on 01/09/2024.
//
//  On Android the imageset is a downscaled rendition of the iOS art, generated (never
//  committed) by Scripts/Android/generate-assets.sh.
//

import SwiftUI

struct AppIcon: View {
    var body: some View {
        Image("AppIcon", bundle: Bundle.faAssets)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 100)
    }
}

#Preview {
    AppIcon()
}
