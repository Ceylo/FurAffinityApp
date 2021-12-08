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
