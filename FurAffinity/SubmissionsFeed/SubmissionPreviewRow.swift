//
//  SubmissionPreviewRow.swift
//  FurAffinity
//
//  Created by Ceylo on 05/07/2026.
//

import SwiftUI
import FAKit

/// A single submission card in a feed/results list: the `SubmissionFeedItemView`
/// wrapped in a full-width, chevron-less navigation link. Shared by the Followed
/// feed and the Explore results list. Feed-only behavior (e.g. scroll-position
/// tracking) is applied by the caller via external modifiers.
struct SubmissionPreviewRow: View {
    let preview: FASubmissionPreview

    var body: some View {
        ZStack(alignment: .leading) {
            NavigationLink(value: FATarget.submission(
                url: preview.url, previewData: preview
            )) {
                // Empty navigation link with 0 opacity is a trick to have full width
                // navigation without a trailing chevron
                EmptyView()
            }
            .opacity(0)

            SubmissionFeedItemView<TitleAuthorHeader>(submission: preview)
                .id(preview.sid)
        }
    }
}
