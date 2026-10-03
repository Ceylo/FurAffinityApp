//
//  View+floatingGlass.swift
//  FurAffinity
//

import SwiftUI

extension View {
    /// `glassEffect` for a control floating over content. Android draws glass as an
    /// opaque M3 surface whose dark shadow is lost on dark content, so in dark mode it
    /// also casts a light one.
    @available(iOS 26, *)
    func floatingGlass(_ glass: Glass = .regular) -> some View {
        glassEffect(glass).darkModeGlow()
    }

    @available(iOS 26, *)
    func floatingGlass(_ glass: Glass = .regular, in shape: some Shape) -> some View {
        glassEffect(glass, in: shape).darkModeGlow()
    }

    private func darkModeGlow() -> some View {
        #if FA_SKIP_MODULE
        modifier(DarkModeGlow())
        #else
        self
        #endif
    }
}

// Not private, nor its @Environment: skipstone can't bridge either.
struct DarkModeGlow: ViewModifier {
    @Environment(\.colorScheme) var colorScheme

    func body(content: Content) -> some View {
        // Within the 5 pt the overlays pad for their shadow: Android clips to bounds
        // while opacity < 1.
        content.shadow(color: .white.opacity(colorScheme == .dark ? 0.5 : 0), radius: 1)
    }
}
