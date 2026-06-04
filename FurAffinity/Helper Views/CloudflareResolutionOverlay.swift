//
//  CloudflareResolutionOverlay.swift
//  FurAffinity
//
//  Created by Ceylo on 31/05/2026.
//

import SwiftUI
import FAKit

/// Non-modal top overlay shown during background CloudFlare resolution.
/// Appears after a short delay so sub-second passive resolutions stay silent.
/// Tapping it opens the interactive sheet immediately.
struct CloudflareResolutionOverlay: View {
    @State private var showPill = false

    var body: some View {
        ZStack {
            if showPill {
                pill
                    .transition(.fallAndFade)
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(1))
            withAnimation { showPill = true }
        }
    }

    @ViewBuilder
    private var pill: some View {
        Button {
            CloudflareChallengeCoordinator.shared.markInteractionRequired()
        } label: {
            if #available(iOS 26, *) {
                pillContent
                    .glassEffect()
            } else {
                pillContent
                    .background(.thinMaterial)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.33), radius: 5, x: 0, y: 0)
            }
        }
        .buttonStyle(.plain)
    }

    private var pillContent: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(spacing: 2) {
                Text("Handling CloudFlare challenge…")
                    .font(.callout)
                Text("Tap to verify manually")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    CloudflareResolutionOverlay()
        .padding()
}
