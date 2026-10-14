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
    /// How long a passive resolution gets to finish before the pill says anything.
    /// Only a preview passes anything but the default.
    var revealDelay: TimeInterval = 1
    // Not private: skipstone can't bridge a private @State/@Environment.
    @State var showPill = false

    private static let animationDuration = 0.35
    /// Transparent room around the pill so its shadow stays inside the animated
    /// view's own bounds — Android clips to those bounds while opacity < 1.
    private static let shadowRadius = 5.0

    /// Same contract as `NotificationOverlay`: an `.id`'d child and the stack's own
    /// animation, never `withAnimation` — this pill shows precisely while a feed is
    /// loading, and on SkipUI that mark would animate the feed too.
    var body: some View {
        ZStack {
            if showPill {
                pill
                    .padding(Self.shadowRadius)
                    .id("pill")
                    .transition(.fallAndFade)
            }
        }
        .animation(.easeInOut(duration: Self.animationDuration), value: showPill)
        .task {
            try? await Task.sleep(for: .seconds(revealDelay))
            showPill = true
        }
    }

    @ViewBuilder
    private var pill: some View {
        Button {
            CloudflareChallengeCoordinator.shared.markInteractionRequired()
        } label: {
            if #available(iOS 26, *) {
                pillContent
                    .floatingGlass()
            } else {
                materialPill
            }
        }
        .buttonStyle(.plain)
    }

    private var materialPill: some View {
        pillContent
            .background(.thinMaterial)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.33), radius: Self.shadowRadius, x: 0, y: 0)
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
    CloudflareResolutionOverlay(revealDelay: 0)
        .padding()
}
