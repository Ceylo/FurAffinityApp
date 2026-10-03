//
//  ScrollToTopButton.swift
//  FurAffinity
//

import SwiftUI

/// A floating arrow that `ScrollToTopReveal` brings in while the list scrolls up,
/// over the top of that list. Stays mounted, and only takes taps while shown.
struct ScrollToTopButton: View {
    let reveal: ScrollToTopReveal
    /// Whether the "new submissions" pill holds the top slot, so this sits under it.
    var belowBadge = false
    let action: () -> Void

    var body: some View {
        Button {
            reveal.dismiss()
            action()
        } label: {
            ActionControl(systemImage: "arrow.up")
                .opaque()
        }
        .accessibilityLabel("Scroll to top")
        .applying {
            if #available(iOS 26, *) {
                $0.floatingGlass()
            } else {
                // Below iOS 26, `ActionControl` draws its own material circle.
                $0.shadow(color: .black.opacity(0.33), radius: NotificationOverlay.shadowRadius)
            }
        }
        // Room for the shadow, as in `NotificationOverlay`.
        .padding(NotificationOverlay.shadowRadius)
        // State-driven rather than a transition, for the same reason as
        // `NotificationOverlay`: these animate on both platforms.
        .opacity(reveal.isShown ? 1 : 0)
        .offset(y: reveal.isShown ? 0 : -12)
        .animation(.easeInOut(duration: 0.25), value: reveal.isShown)
        .offset(y: belowBadge ? NotificationOverlay.badgeHeight : 0)
        .animation(.easeInOut(duration: 0.35), value: belowBadge)
        .allowsHitTesting(reveal.isShown)
        .accessibilityHidden(!reveal.isShown)
        .task(id: reveal.isShown) {
            while let deadline = reveal.idleDeadline {
                do {
                    try await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow)))
                } catch { return }
                reveal.hideIfIdle()
            }
        }
        // Covered, the timer stops: hide now rather than fade out a stale arrow on return.
        .onDisappear {
            reveal.hide()
        }
    }
}

#Preview(traits: .sizeThatFitsLayout) {
    let reveal = ScrollToTopReveal()
    reveal.idleDelay = 3600
    // Scrolled away from the top, then back up.
    reveal.record(id: 1, minY: -10)
    reveal.record(id: 1, minY: 30)

    return HStack(alignment: .top, spacing: 16) {
        ScrollToTopButton(reveal: reveal) {}
        ZStack(alignment: .top) {
            NotificationOverlay(itemCount: .constant(12), dismissAfter: 3600)
            ScrollToTopButton(reveal: reveal, belowBadge: true) {}
        }
    }
    .padding()
    .background(Color.cyan)
}
