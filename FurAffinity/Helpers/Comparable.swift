//
//  Comparable.swift
//  FurAffinity
//
//  Created by Ceylo on 15/06/2024.
//

#if !FA_SKIP_MODULE

import Foundation

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(range.upperBound, max(range.lowerBound, self))
    }
}

#endif
