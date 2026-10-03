//
//  ScrollToTopRevealTests.swift
//  FurAffinityTests
//

import Foundation
import Testing
#if FA_SKIP_MODULE
@testable import FurAffinityUI
#else
@testable import Fur_Affinity
#endif

@MainActor
struct ScrollToTopRevealTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 0)
    /// Long enough before `start` that a rebase's settling is over.
    private static let settled = start.addingTimeInterval(-1)

    /// Scrolled well past the first row, with row 5 as the reference at 100.
    private func scrolledDown() -> ScrollToTopReveal {
        let reveal = ScrollToTopReveal()
        reveal.rebase(firstID: 0, now: Self.settled)
        reveal.record(id: 0, minY: nil, now: Self.start)
        reveal.record(id: 4, minY: -50, now: Self.start)
        reveal.record(id: 4, minY: nil, now: Self.start)
        reveal.record(id: 5, minY: 100, now: Self.start)
        return reveal
    }

    @Test func revealsAfterRevealDistanceUp() {
        let reveal = scrolledDown()
        reveal.record(id: 5, minY: 120, now: Self.start)
        #expect(!reveal.isShown)
        reveal.record(id: 5, minY: 130, now: Self.start)
        #expect(reveal.isShown)
    }

    @Test func downwardTravelResetsUpwardTravel() {
        let reveal = scrolledDown()
        reveal.record(id: 5, minY: 125, now: Self.start)
        reveal.record(id: 5, minY: 120, now: Self.start)
        reveal.record(id: 5, minY: 145, now: Self.start)
        #expect(!reveal.isShown)
    }

    @Test func hidesAfterRevealDistanceDown() {
        let reveal = scrolledDown()
        reveal.record(id: 5, minY: 140, now: Self.start)
        #expect(reveal.isShown)
        reveal.record(id: 5, minY: 120, now: Self.start)
        #expect(reveal.isShown)
        reveal.record(id: 5, minY: 110, now: Self.start)
        #expect(!reveal.isShown)
    }

    @Test func neverRevealsNearTop() {
        let reveal = ScrollToTopReveal()
        reveal.rebase(firstID: 0, now: Self.settled)
        reveal.record(id: 1, minY: 220, now: Self.start)
        reveal.record(id: 0, minY: 10, now: Self.start)
        reveal.record(id: 1, minY: 300, now: Self.start)
        #expect(!reveal.isShown)
    }

    @Test func hidesOnReachingTop() {
        let reveal = scrolledDown()
        reveal.record(id: 5, minY: 200, now: Self.start)
        #expect(reveal.isShown)
        reveal.record(id: 0, minY: -150, now: Self.start)
        #expect(!reveal.isShown)
    }

    @Test func laterRowAboveTheListMeansAwayFromTop() {
        let reveal = ScrollToTopReveal()
        reveal.rebase(firstID: 0, now: Self.settled)
        // The first row reported, then got recycled without reporting it left.
        reveal.record(id: 0, minY: 10, now: Self.start)
        let later = Self.start.addingTimeInterval(1)
        reveal.record(id: 3, minY: -10, now: later)
        reveal.record(id: 3, minY: 30, now: later)
        #expect(reveal.isShown)
    }

    @Test func handsSilentReferenceOver() {
        let reveal = scrolledDown()
        // Row 5 was recycled without reporting it left.
        reveal.record(id: 6, minY: 400, now: Self.start.addingTimeInterval(0.1))
        reveal.record(id: 6, minY: 450, now: Self.start.addingTimeInterval(0.2))
        #expect(!reveal.isShown)
        reveal.record(id: 6, minY: 460, now: Self.start.addingTimeInterval(0.3))
        reveal.record(id: 6, minY: 490, now: Self.start.addingTimeInterval(0.3))
        #expect(reveal.isShown)
    }

    @Test func handsReferenceOverWhenItLeaves() {
        let reveal = scrolledDown()
        reveal.record(id: 5, minY: nil, now: Self.start)
        // Row 6 becomes the reference: its first report is no motion.
        reveal.record(id: 6, minY: 400, now: Self.start)
        #expect(!reveal.isShown)
        reveal.record(id: 6, minY: 430, now: Self.start)
        #expect(reveal.isShown)
    }

    @Test func otherRowsDontMeasure() {
        let reveal = scrolledDown()
        reveal.record(id: 6, minY: 300, now: Self.start)
        reveal.record(id: 6, minY: 400, now: Self.start)
        #expect(!reveal.isShown)
    }

    @Test func rebaseIgnoresTheJump() {
        let reveal = scrolledDown()
        reveal.rebase(firstID: -1, now: Self.settled)
        // Rows inserted above moved the reference down without any scrolling.
        reveal.record(id: 5, minY: 900, now: Self.start)
        #expect(!reveal.isShown)
        reveal.record(id: 5, minY: 930, now: Self.start)
        #expect(reveal.isShown)
    }

    @Test func rebaseIgnoresRowsSlidingIntoPlace() {
        let reveal = scrolledDown()
        reveal.rebase(firstID: -1, now: Self.start)
        for (step, minY) in [140.0, 180, 220].enumerated() {
            reveal.record(id: 5, minY: minY, now: Self.start.addingTimeInterval(0.1 * Double(step)))
        }
        #expect(!reveal.isShown)
        reveal.record(id: 5, minY: 250, now: Self.start.addingTimeInterval(0.5))
        #expect(reveal.isShown)
    }

    @Test func ignoresAJump() {
        let reveal = scrolledDown()
        // A programmatic scroll to the top, before the first row shows.
        reveal.record(id: 5, minY: 421, now: Self.start)
        #expect(!reveal.isShown)
        reveal.record(id: 5, minY: 451, now: Self.start)
        #expect(reveal.isShown)
    }

    @Test func hideForgetsTheReference() {
        let reveal = scrolledDown()
        reveal.hide()
        // The row drifted while the list was covered.
        reveal.record(id: 5, minY: 150, now: Self.start)
        #expect(!reveal.isShown)
        reveal.record(id: 5, minY: 180, now: Self.start)
        #expect(reveal.isShown)
    }

    @Test func rebaseStartsTravelOver() {
        let reveal = scrolledDown()
        reveal.record(id: 5, minY: 125, now: Self.start)
        reveal.rebase(firstID: 0, now: Self.settled)
        reveal.record(id: 5, minY: 125, now: Self.start)
        reveal.record(id: 5, minY: 135, now: Self.start)
        #expect(!reveal.isShown)
    }

    @Test func hideEndsATapsSuppression() {
        let reveal = scrolledDown()
        reveal.record(id: 5, minY: 140, now: Self.start)
        reveal.dismiss()
        // Covered before the scroll to the top arrived.
        reveal.hide()
        reveal.record(id: 5, minY: 140, now: Self.start)
        reveal.record(id: 5, minY: 170, now: Self.start)
        #expect(reveal.isShown)
    }

    @Test func hideStartsOver() {
        let reveal = scrolledDown()
        reveal.record(id: 5, minY: 140, now: Self.start)
        reveal.hide()
        #expect(!reveal.isShown)
        reveal.record(id: 5, minY: 150, now: Self.start)
        #expect(!reveal.isShown)
    }

    @Test func dismissSuppressesUntilTop() {
        let reveal = scrolledDown()
        reveal.record(id: 5, minY: 140, now: Self.start)
        reveal.dismiss()
        #expect(!reveal.isShown)
        // The scroll to the top the tap triggered.
        reveal.record(id: 5, minY: 400, now: Self.start)
        #expect(!reveal.isShown)
        reveal.record(id: 0, minY: 10, now: Self.start)
        reveal.record(id: 0, minY: nil, now: Self.start)
        reveal.record(id: 5, minY: -10, now: Self.start)
        reveal.record(id: 5, minY: 30, now: Self.start)
        #expect(reveal.isShown)
    }

    @Test func dismissSuppressionEndsOnDownwardTravel() {
        let reveal = scrolledDown()
        reveal.record(id: 5, minY: 140, now: Self.start)
        reveal.dismiss()
        reveal.record(id: 5, minY: 100, now: Self.start)
        reveal.record(id: 5, minY: 140, now: Self.start)
        #expect(reveal.isShown)
    }

    @Test func hidesWhenIdle() throws {
        let reveal = scrolledDown()
        #expect(reveal.idleDeadline == nil)
        reveal.record(id: 5, minY: 140, now: Self.start)
        let later = Self.start.addingTimeInterval(1)
        reveal.record(id: 5, minY: 150, now: later)
        let deadline = try #require(reveal.idleDeadline)
        #expect(deadline == later.addingTimeInterval(reveal.idleDelay))

        reveal.hideIfIdle(now: deadline.addingTimeInterval(-0.1))
        #expect(reveal.isShown)
        reveal.hideIfIdle(now: deadline)
        #expect(!reveal.isShown)

        // Going up again starts over from zero.
        reveal.record(id: 5, minY: 160, now: deadline)
        #expect(!reveal.isShown)
    }
}
