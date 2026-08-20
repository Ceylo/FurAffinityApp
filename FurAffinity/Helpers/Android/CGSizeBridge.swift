//
//  CGSizeBridge.swift
//  FurAffinityUI (Skip)
//
//  SkipSwiftUI vendors its *own* `CGSize` (returned by `GeometryProxy.size`, etc.),
//  distinct from the `Foundation.CGSize` that FAKit's sizing helpers extend and that
//  its `bestThumbnailUrl(for:)` takes. This initializer bridges the former into the
//  latter so callers can `Foundation.CGSize(geometry.size)`.
//
//  It lives in its own file on purpose: `import SkipSwiftUI` (needed to name the
//  source type) makes `GeometryProxy` ambiguous, so no file that touches
//  `GeometryProxy` may import it. This file names neither.
//
//  Android/Skip only (not part of the iOS Xcode target); on Apple platforms there is a
//  single CGSize and no bridge is needed.
//

import Foundation
import SkipSwiftUI

extension Foundation.CGSize {
    init(_ size: SkipSwiftUI.CGSize) {
        self.init(width: size.width, height: size.height)
    }
}
