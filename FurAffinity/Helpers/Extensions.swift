//
//  Extensions.swift
//  FurAffinity
//
//  Created by Ceylo on 08/12/2021.
//

import SwiftUI

extension Color {
    static let borderOverlay = Color("BorderOverlay")
}

extension CGPoint {
    static func+(lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        .init(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
}

extension UIScrollView {
    var reachedTop: Bool {
        return contentOffset.y - adjustedContentInset.top <= 0
    }
}

extension URL {
    func replacingScheme(with newScheme: String) -> URL? {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = newScheme
        return components.url
    }
}
