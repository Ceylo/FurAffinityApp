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
//  - Comment posting and note sending are out of scope for the port: SkipSwiftUI has no
//    `ObservableObject`/`@StateObject`, which the whole Replying/CommentEditor machinery
//    is built on. The sheets are no-ops and their sessions are never set.
//  - `share` / `exportToFiles` land in step 4 (FAMediaBridge).
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

    /// Scrolling a deep-linked comment into view is not ported.
    ///
    /// The iOS modifier nests its `content` inside a `ScrollViewReader` closure, and
    /// that crashes the app on Android: `ViewModifier.Content` arrives as a JNI *local*
    /// reference, valid only for the frame that built the modifier, while the reader's
    /// closure is invoked later from Compose — "jobject is an invalid JNI transition
    /// frame reference". Any modifier that defers use of `content` into an escaping
    /// closure hits this.
    func scrollToItem(id: (some Hashable)?) -> some View { self }
}

// MARK: - Replying (not ported)

/// Kept so `SubmissionView`'s `@State` and its `.init(parentCid:among:)` call sites
/// compile; nothing sets it, because no editor can be presented.
struct CommentReplySession {
    let parentCid: Int?

    init(parentCid: Int?, among comments: [FAComment]) {
        self.parentCid = parentCid
    }
}

struct NoteReplySession {
    struct DefaultContents {
        let destinationUser: String
        let subject: String
        let text: String

        init(destinationUser: String = "", subject: String = "", text: String = "") {
            self.destinationUser = destinationUser
            self.subject = subject
            self.text = text
        }
    }

    let defaultContents: DefaultContents
}

/// The reply payload `SubmissionView.replyAction` is typed against.
final class CommentReply {
    var commentText: String = ""
}

struct NoteReply {
    var destinationUser = ""
    var subject = ""
    var text = ""
}

extension View {
    func commentSheet(
        on replySession: Binding<CommentReplySession?>,
        _ replyAction: @MainActor @escaping (_ parentCid: Int?, _ reply: CommentReply) async throws -> Void
    ) -> some View {
        self
    }

    func noteReplySheet(
        on replySession: Binding<NoteReplySession?>,
        _ replyAction: @MainActor @escaping (_ reply: NoteReply) async throws -> Void
    ) -> some View {
        self
    }

    /// Focusing a deep-linked comment needs the collapse machinery from step 6.
    func autoFocusingDeepHighlight(
        in comments: [FAComment],
        targetCid: Int?,
        acceptsNewReplies: Bool,
        replyAction: ((_ cid: Int) -> Void)?
    ) -> some View {
        self
    }
}

// MARK: - Sharing (step 4)

@MainActor
func share(_ items: [Any]) {
    logger.info("share() is not implemented on Android yet")
}

@MainActor
func exportToFiles(_ urls: [URL]) {
    logger.info("exportToFiles() is not implemented on Android yet")
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
