//
//  CommentFocusTargetTests.swift
//  FurAffinityTests
//
//  Created by Ceylo on 20/06/2026.
//

import Testing
import Foundation
import FAKit
@testable import Fur_Affinity

struct CommentFocusTargetTests {
    /// root(0) → a(1) → b(2) → c(3) → d(4) → e(5): a single chain so each cid sits at a
    /// known 0-based depth.
    private static func chain() -> [FAComment] {
        func node(_ cid: Int, _ answers: [FAComment]) -> FAComment {
            .hidden(.init(cid: cid, message: AttributedString(""), answers: answers))
        }
        return [node(0, [node(1, [node(2, [node(3, [node(4, [node(5, [])])])])])])]
    }

    @Test
    func focusesOnTargetParentWhenDeeperThanCutoff() {
        // Target e is at depth 5; with cutoff 3 it exceeds the cutoff and must auto-focus.
        let focus = deepHighlightFocus(in: Self.chain(), targetCid: 5, cutoff: 3)
        // Focused cid is the target's PARENT (d), so e re-bases to depth 1.
        #expect(focus?.focusedCid == 4)
        // Thread root is the top-level ancestor for context.
        #expect(focus?.threadRoot.cid == 0)
    }

    @Test
    func gateFiresOnlyWhenDepthExceedsCutoff() {
        // Target e at depth 5.
        #expect(deepHighlightFocus(in: Self.chain(), targetCid: 5, cutoff: 4) != nil)  // 5 > 4
        #expect(deepHighlightFocus(in: Self.chain(), targetCid: 5, cutoff: 5) == nil)  // 5 == 5
        #expect(deepHighlightFocus(in: Self.chain(), targetCid: 5, cutoff: 6) == nil)  // 5 < 6
    }

    @Test
    func noFocusForShallowTarget() {
        // Target b at depth 2 stays inline under cutoff 3.
        #expect(deepHighlightFocus(in: Self.chain(), targetCid: 2, cutoff: 3) == nil)
    }

    @Test
    func noFocusWhenTargetMissingOrNil() {
        #expect(deepHighlightFocus(in: Self.chain(), targetCid: nil, cutoff: 3) == nil)
        #expect(deepHighlightFocus(in: Self.chain(), targetCid: 999, cutoff: 3) == nil)
    }
}
