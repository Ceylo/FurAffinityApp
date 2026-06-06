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
            // Prefer the full wording; fall back to a shorter variant when it
            // would otherwise overflow one line (e.g. larger Dynamic Type on a
            // narrow screen). The last variant scales/truncates as a final guard.
            ViewThatFits(in: .horizontal) {
                labels("Handling CloudFlare challenge…", "Tap to verify manually")
                labels("CloudFlare challenge…", "Tap to see")
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func labels(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.callout)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .lineLimit(1)
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    CloudflareResolutionOverlay()
        .padding()
}
