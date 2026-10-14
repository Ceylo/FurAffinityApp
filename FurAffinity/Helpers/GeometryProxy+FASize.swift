//
//  GeometryProxy+FASize.swift
//  FurAffinity
//
//  Created by Ceylo on 24/07/2026.
//

import Foundation
import SwiftUI

extension GeometryProxy {
    /// `size` as a `Foundation.CGSize`. On the Skip build `GeometryProxy.size` is
    /// SkipSwiftUI's own `CGSize`, which FAKit's sizing helpers don't extend and which
    /// `bestThumbnailUrl(for:)` won't accept; the bridging initializer converts it. On
    /// Apple platforms there is a single `CGSize`, so this is just `size`.
    ///
    /// `FA_SKIP_MODULE` (not `os(Android)`) because the Skip module's Darwin bridge is
    /// also compiled with the façade's `CGSize`, yet `os(Android)` is false there.
    var faSize: Foundation.CGSize {
        #if FA_SKIP_MODULE
        Foundation.CGSize(size)
        #else
        size
        #endif
    }
}
