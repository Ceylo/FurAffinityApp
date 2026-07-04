//
//  GlassCircleLabel.swift
//  FurAffinity
//
//  Created by Ceylo on 04/07/2026.
//

import SwiftUI

/// A round Liquid-Glass icon button label, matching `ActionControl().opaque()`
/// but for an arbitrary SF Symbol (the mode switch and filters buttons).
struct GlassCircleLabel: View {
    let systemImage: String
    var size: Double = 18

    var body: some View {
        if #available(iOS 26, *) {
            Image(systemName: systemImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .tint(.primary)
                .frame(width: size, height: size)
                .padding(13)
                .glassEffect()
        } else {
            Image(systemName: systemImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .foregroundColor(.accentColor)
                .padding(5)
                .background(.thinMaterial)
                .clipShape(Circle())
                .padding(5)
        }
    }
}

#Preview {
    GlassCircleLabel(systemImage: "heart")
}
