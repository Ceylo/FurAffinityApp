//
//  NotificationOverlay.swift
//  FurAffinity
//
//  Created by Ceylo on 07/01/2022.
//

import SwiftUI

extension AnyTransition {
    static var fallAndFade: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        )
    }
}

/// `fallAndFade` as state rather than a transition: SkipUI resolves transitions in
/// the container, where it only sees a global `withAnimation` mark — but `.opacity`
/// and `.offset` read the animation themselves, so these two animate on both
/// platforms. Fading keeps the offset at 0, which is what made it asymmetric.
enum NotificationOverlayPhase {
    /// Above its place and transparent — where the badge falls in from.
    case hidden
    case shown
    /// Transparent again, without moving.
    case fading
}

struct NotificationOverlay: View {
    @Binding var itemCount: Int?
    var dismissAfter: TimeInterval = 3.0
    /// State on a bridged view must be internal, not private (Skip inventory #5).
    /// Outlives `itemCount` so the text survives the fade-out.
    @State var lastCount = 0
    @State var phase = NotificationOverlayPhase.hidden

    private static let animationDuration = 0.35
    /// The pill's own height, so it falls in from exactly out of place.
    private static let badgeHeight = 44.0

    private func text(count: Int) -> String {
        switch count {
        case 0: return "No new submission"
        case 1: return "1 new submission"
        default: return "\(count) new submissions"
        }
    }
    
    /// SkipUI has no Liquid Glass, so Android always uses the material badge.
    @ViewBuilder
    func badge(_ count: Int) -> some View {
#if os(Android)
        materialBadge(count)
#else
        if #available(iOS 26, *) {
            Text(text(count: count))
                .font(.callout)
                .foregroundColor(Color.primary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .glassEffect()
        } else {
            materialBadge(count)
        }
#endif
    }

    func materialBadge(_ count: Int) -> some View {
        Text(text(count: count))
            .font(.callout)
            .foregroundColor(Color.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            // Regular, not thin: Android has no blur, our skip-fuse-ui fork renders a
            // material as a flat scrim (thin 0.45, regular 0.6), and 0.45 left the pill
            // unreadable over a light list gap.
            .background(.regularMaterial)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.33) , radius: 5, x: 0, y: 0)
    }
    
    /// The badge stays mounted and drives itself, so it must not eat taps meant for
    /// what it floats over.
    var body: some View {
        badge(lastCount)
            .opacity(phase == .shown ? 1 : 0)
            .offset(y: phase == .hidden ? -Self.badgeHeight : 0)
            // Keyed on the visibility, not on `phase`: `fading → hidden` then carries no
            // animation, which is exactly what should snap — both phases are transparent,
            // so the offset going back up must not be animated.
            .animation(.easeInOut(duration: Self.animationDuration), value: phase == .shown)
            .allowsHitTesting(false)
            .task(id: itemCount) {
                guard let itemCount else { return }
                lastCount = itemCount
                phase = .shown

                // On cancellation just return: a new count is about to restart this,
                // and writing then would fight it.
                do { try await Task.sleep(for: .seconds(dismissAfter)) } catch { return }
                phase = .fading
                // Only go back up once the fade has played, otherwise the reset rides
                // along with it.
                do { try await Task.sleep(for: .seconds(Self.animationDuration)) } catch { return }
                phase = .hidden
                self.itemCount = nil
            }
    }
}

private struct Checkerboard: Shape {
    let rows: Int
    let columns: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // figure out how big each row/column needs to be
        let rowSize = rect.height / Double(rows)
        let columnSize = rect.width / Double(columns)

        // loop over all rows and columns, making alternating squares colored
        for row in 0 ..< rows {
            for column in 0 ..< columns {
                if (row + column).isMultiple(of: 2) {
                    // this square should be colored; add a rectangle here
                    let startX = columnSize * Double(column)
                    let startY = rowSize * Double(row)

                    let rect = CGRect(x: startX, y: startY, width: columnSize, height: rowSize)
                    path.addRect(rect)
                }
            }
        }

        return path
    }
}

#if !FA_SKIP_MODULE
#Preview(traits: .sizeThatFitsLayout) {
    NotificationOverlay(itemCount: .constant(12))
        .padding()
        .background(Checkerboard(rows: 5, columns: 16).fill(.cyan))
}
#endif
