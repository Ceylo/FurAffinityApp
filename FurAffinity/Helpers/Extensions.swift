//
//  Extensions.swift
//  FurAffinity
//
//  Created by Ceylo on 08/12/2021.
//

import SwiftUI

extension CGSize {
    var maxDimension: CGFloat { max(width, height) }
}

extension Color {
    static let borderOverlay = Color("BorderOverlay")
}

extension CGPoint {
    static func+(lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        .init(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
}
