//
//  SubmissionShims.swift
//  FurAffinityUI (Android)
//
//  The small Android substitutes that let `RemoteView.swift` and `SubmissionView.swift`
//  be symlinked *verbatim* from the iOS sources. Each keeps the iOS name and signature;
//  what's missing on Android is the framework behind it, not the call site.
//
//  - `NSUserActivity` / `defaultScrollAnchor`: no Android equivalent, and neither
//    affects what is drawn.
//  - `share` / `exportToFiles` go through FAMediaBridge. This is also the only
//    `share(_:)` on Android, so Settings' log export uses it too.
//

import Foundation
import SwiftUI
import FAKit

// MARK: - Handoff

/// Handoff has no Android counterpart. `RemoteView` only ever creates one, sets its
/// `webpageURL` and makes it current, so a value type with those members is enough.
let NSUserActivityTypeBrowsingWeb = "com.apple.browsing.web"

final class NSUserActivity: Equatable {
    let activityType: String
    var webpageURL: URL?

    init(activityType: String) {
        self.activityType = activityType
    }

    func becomeCurrent() {}
    func resignCurrent() {}

    static func == (lhs: NSUserActivity, rhs: NSUserActivity) -> Bool {
        lhs === rhs
    }
}

extension View {
    /// SkipSwiftUI has no scroll anchor; only used to centre a failure message.
    func defaultScrollAnchor(_ anchor: UnitPoint) -> some View { self }
}

// MARK: - Sharing

/// The iOS signature is `[Any]` because `UIActivityViewController` takes anything;
/// every call site in the ported screens passes a single local file URL.
@MainActor
func share(_ items: [Any]) {
    guard let url = items.compactMap({ $0 as? URL }).first else {
        logger.error("share() called with no file URL")
        return
    }
    Task { _ = await MediaBridge.shareOffMain(fileUrl: url) }
}

/// Saves into Download/FurAffinity, which the Files app shows, rather than asking where
/// as iOS's document picker does. The iOS signature carries no error storage, so a
/// failure is only logged; `FAMediaBridge` confirms a success in a toast.
@MainActor
func exportToFiles(_ urls: [URL]) {
    for url in urls {
        Task {
            if !(await MediaBridge.saveDocumentOffMain(atFileUrl: url)) {
                logger.error("exportToFiles could not save \(url.lastPathComponent)")
            }
        }
    }
}

// MARK: - Thumbnails

extension DynamicThumbnail {
    /// FAKit's `bestThumbnailUrl(for: GeometryProxy)` is `#if canImport(SwiftUI)`, and
    /// FAKit doesn't depend on SkipSwiftUI — so on Android only the `CGSize` overload
    /// exists. This restores the geometry one for symlinked callers.
    func bestThumbnailUrl(for geometry: GeometryProxy) -> URL {
        bestThumbnailUrl(for: geometry.faSize)
    }
}
