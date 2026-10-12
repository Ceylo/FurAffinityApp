//
//  ScrollToTopReveal.swift
//  FurAffinity
//

// SwiftUI rather than Observation: on Android an @Observable only recomposes with
// SkipAndroidBridge visible, which SwiftUI brings.
import SwiftUI

/// Decides when a list's scroll-to-top button shows: after a short scroll up, away
/// from the top, until the scrolling stops, turns down, or reaches the top.
///
/// Fed from the per-row frame reports a list already gets (`onItemFrameChanged`)
/// rather than from the scroll view, which SkipUI doesn't expose. Only `isShown` is
/// observed: the rest changes on every scroll frame and must not invalidate the host.
@Observable
@MainActor
final class ScrollToTopReveal {
    private(set) var isShown = false

    /// How far the list must travel up to show the button, or down to hide it.
    @ObservationIgnored var revealDistance: Double = 30
    /// How long the button stays once the scrolling up stops.
    @ObservationIgnored var idleDelay: TimeInterval = 2.5

    private static let staleReferenceAge: TimeInterval = 0.25
    /// Further than this between two reports is a jump, not scrolling: Android's tab
    /// re-tap scroll moved the reference 321 then 592 pt per report, a fling at most ~120.
    private static let jumpDistance: Double = 200
    /// How long after `rebase` the rows may still be sliding into place.
    private static let settlingDelay: TimeInterval = 0.4

    @ObservationIgnored private var firstID: AnyHashable?
    /// The row whose successive `minY`s measure the scrolling.
    @ObservationIgnored private var referenceID: AnyHashable?
    @ObservationIgnored private var lastMinY: Double = 0
    @ObservationIgnored private var lastReferenceReport = Date.distantPast
    /// Up is positive. Turning around starts it over.
    @ObservationIgnored private var travel: Double = 0
    @ObservationIgnored private var isNearTop = true
    /// Set by a tap, so the scroll back up it triggers can't bring the button back.
    @ObservationIgnored private var suppressedUntilTop = false
    @ObservationIgnored private var lastUpwardMotion = Date.distantPast
    @ObservationIgnored private var settledAt = Date.distantPast

    /// When the button hides unless the list keeps going up; `nil` while hidden.
    var idleDeadline: Date? {
        isShown ? lastUpwardMotion.addingTimeInterval(idleDelay) : nil
    }

    /// Call when the rows change: an insertion or removal moves the reference row
    /// without any scrolling, at once or animated.
    func rebase(firstID: AnyHashable?, now: Date = .now) {
        self.firstID = firstID
        referenceID = nil
        travel = 0
        settledAt = now.addingTimeInterval(Self.settlingDelay)
    }

    /// Call with every row frame report: its `minY` in the list, `nil` once the row
    /// leaves it. A `Double` because a SwiftUI `CGRect` is a different type on Skip.
    func record(id: AnyHashable, minY: Double?, now: Date = .now) {
        if id == firstID {
            isNearTop = minY != nil
        } else if let minY, minY <= 0 {
            // The first row is above this one, so off the list. Needed because a row
            // can be recycled without reporting it left.
            isNearTop = false
        }

        defer { evaluate() }
        guard let minY else {
            if id == referenceID { referenceID = nil }
            return
        }
        guard id == referenceID else {
            // Visible rows report together, so a reference silent while another row
            // moves was recycled without reporting it left.
            if referenceID == nil || now.timeIntervalSince(lastReferenceReport) > Self.staleReferenceAge {
                referenceID = id
                lastMinY = minY
                lastReferenceReport = now
            }
            return
        }

        lastReferenceReport = now
        let delta = minY - lastMinY
        lastMinY = minY
        guard delta != 0, abs(delta) <= Self.jumpDistance, now >= settledAt else {
            return
        }
        travel = (travel.sign == delta.sign ? travel : 0) + delta
        if delta > 0 { lastUpwardMotion = now }
    }

    /// Call on tap, before scrolling to the top.
    func dismiss() {
        suppressedUntilTop = true
        travel = min(travel, 0)
        setShown(false)
    }

    /// Hides the button if the list hasn't gone up since `idleDeadline`.
    func hideIfIdle(now: Date = .now) {
        guard let idleDeadline, now >= idleDeadline else { return }
        hide()
    }

    /// Also forgets the reference row, which may have moved by the time reports
    /// resume, and a tap's suppression, whose scroll may never have finished.
    func hide() {
        referenceID = nil
        suppressedUntilTop = false
        travel = min(travel, 0)
        setShown(false)
    }

    private func evaluate() {
        if isNearTop || travel <= -revealDistance {
            suppressedUntilTop = false
            travel = min(travel, 0)
            setShown(false)
        } else if travel >= revealDistance && !suppressedUntilTop {
            setShown(true)
        }
    }

    /// Only on change: this runs for every scroll frame.
    private func setShown(_ shown: Bool) {
        if isShown != shown { isShown = shown }
    }
}
