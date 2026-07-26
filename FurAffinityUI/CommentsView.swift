//
//  CommentsView.swift
//  FurAffinityUI (Android)
//
//  Placeholder so `SubmissionView` symlinks verbatim. The real threaded renderer —
//  connector lines, avatars, collapsed sub-threads — is ported in step 6; this file is
//  deleted then, in favour of symlinks to `Comments/`.
//

import SwiftUI
import FAKit

struct CommentsView: View {
    var comments: [FAComment]
    var highlightedCommentId: Int?
    var acceptsNewReplies: Bool
    var replyAction: ((_ cid: Int) -> Void)?

    var body: some View {
        Text("Comments aren't on Android yet.")
            .foregroundStyle(.secondary)
            .padding()
            .frame(maxWidth: .infinity)
    }
}
