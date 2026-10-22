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
/// feed, the Explore results list and the user's gallery and favorites.
/// Feed-only behavior (e.g. scroll-position tracking) is applied by the caller via
/// external modifiers.
struct SubmissionPreviewRow<Header: SubmissionHeaderView>: View {
    let preview: FASubmissionPreview

    var body: some View {
        #if os(Android)
        // SkipUI lays the opacity-0 NavigationLink out at its intrinsic (empty) size
        // rather than stretching it behind the card, so only a narrow leading strip
        // of the row reacts. FALink's button covers the whole row instead.
        FALink(destination: .submission(url: preview.url, previewData: preview)) {
            SubmissionFeedItemView<Header>(submission: preview)
        }
        .withFullWidthTapArea()
        #else
        ZStack(alignment: .leading) {
            NavigationLink(value: FATarget.submission(
                url: preview.url, previewData: preview
            )) {
                // Empty navigation link with 0 opacity is a trick to have full width
                // navigation without a trailing chevron
                EmptyView()
            }
            .opacity(0)

            SubmissionFeedItemView<Header>(submission: preview)
        }
        #endif
    }
}
