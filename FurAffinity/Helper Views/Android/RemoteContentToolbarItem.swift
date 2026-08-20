//
//  RemoteContentToolbarItem.swift
//  FurAffinityUI (Android)
//
//  Android counterpart of the iOS `RemoteContentToolbarItem`. Identical menu — Open in
//  Web Browser, Share Link, then the caller's items — and identical code, save for one
//  string: the share message says "for Android" where the iOS one says "for iPhone".
//  That is the only reason this isn't a symlink.
//
//  Nothing shows that message yet: SkipUI's `ShareLink` only puts EXTRA_TEXT and
//  EXTRA_SUBJECT in the intent and drops `message` on the floor.
//

import SwiftUI
import Defaults

struct RemoteContentToolbarItem<ContentsView: View>: ToolbarContent {
    init(url: URL, @ViewBuilder additionalToolbarItems: @escaping () -> ContentsView = { EmptyView() }) {
        self.url = url
        self.additionalToolbarItems = additionalToolbarItems
    }

    var url: URL
    var additionalToolbarItems: () -> ContentsView
    @Default(.addMessageToSharedItems) private var addMessageToSharedItems

    private var shareMessage: Text? {
        guard addMessageToSharedItems else {
            return nil
        }
        return Text("Sent from the FurAffinity unofficial App for Android (https://furaffinity.app/)")
    }

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Link(destination: url) {
                    Label("Open in Web Browser", systemImage: "safari")
                }
                ShareLink(
                    item: url,
                    message: shareMessage
                ) {
                    Label("Share Link", systemImage: "square.and.arrow.up")
                }
                Divider()
                additionalToolbarItems()
            } label: {
                ActionControl()
            }
        }
    }
}
