//
//  Extensions.swift
//  FurAffinity
//
//  Created by Ceylo on 08/12/2021.
//

import SwiftUI

extension CGPoint {
    static func+(lhs: CGPoint, rhs: CGPoint) -> CGPoint {
        .init(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
}

extension UIScrollView {
    var reachedTop: Bool {
        return abs(contentOffset.y + adjustedContentInset.top) < 1e-6
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
