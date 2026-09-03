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
    @State var phase = NotificationOverlayPhase.hidden

    private static let animationDuration = 0.35
    /// Transparent room around the pill so its shadow stays inside the animated
    /// view's own bounds — Android clips to those bounds while opacity < 1.
    private static let shadowRadius = 5.0
    /// The padded pill's height, so it falls in from exactly out of place.
    private static let pillHeight = 60.0 + 2 * shadowRadius

    /// Same state-driven `fallAndFade` as `NotificationOverlay`: SkipUI resolves a
    /// `.transition` in the container, where it only sees a process-global
    /// `withAnimation` mark — and this pill shows precisely while a feed is loading,
    /// so that mark would animate the feed too.
    var body: some View {
        pill
            .padding(Self.shadowRadius)
            .opacity(phase == .shown ? 1 : 0)
            .offset(y: phase == .hidden ? -Self.pillHeight : 0)
            .animation(.easeInOut(duration: Self.animationDuration), value: phase == .shown)
            .accessibilityHidden(phase != .shown)
            // Unlike NotificationOverlay this one must stay hit-testable once shown:
            // tapping it is the only way to reach the interactive sheet on demand.
            // Not while transparent though, or it eats taps meant for what it floats over.
            .allowsHitTesting(phase == .shown)
            .task {
                try? await Task.sleep(for: .seconds(revealDelay))
                phase = .shown
            }
    }

    @ViewBuilder
    private var pill: some View {
        Button {
            CloudflareChallengeCoordinator.shared.markInteractionRequired()
        } label: {
            // SkipUI has no Liquid Glass, and `#available(iOS 26, *)` is vacuously
            // true off-Apple, so Android always takes the material branch.
#if os(Android)
            materialPill
#else
            if #available(iOS 26, *) {
                pillContent
                    .glassEffect()
            } else {
                materialPill
            }
#endif
        }
        .buttonStyle(.plain)
    }

    private var materialPill: some View {
        pillContent
            // Android has no blur — our skip-fuse-ui fork renders a material as a flat
            // scrim, so thickness is literally opacity and thin is unreadable over
            // artwork. On iOS the material is a real blur, so thin reads.
#if os(Android)
            .background(.ultraThickMaterial)
#else
            .background(.thinMaterial)
#endif
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

#if !FA_SKIP_MODULE
#Preview(traits: .sizeThatFitsLayout) {
    CloudflareResolutionOverlay(revealDelay: 0)
        .padding()
}
#endif
