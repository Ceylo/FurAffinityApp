//
//  RemoteContentToolbarItem.swift
//  FurAffinityUI (Android)
//
//  Android counterpart of the iOS `RemoteContentToolbarItem`. Identical menu — Open in
//  Web Browser, Share Link, then the caller's items — but it can't be symlinked: the
//  iOS one reads its share-message preference through `@Default`, and the Defaults
//  fork compiles its whole SwiftUI layer out on Android (`@Default` is built on
//  `@StateObject`, which SkipSwiftUI doesn't have).
//
//  Reading `Defaults[...]` directly costs only live updates while the menu is open,
//  which no user can observe: the settings screen isn't ported.
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

    private var shareMessage: Text? {
        guard Defaults[.addMessageToSharedItems] else {
            return nil
        }
        return Text("Sent from the FurAffinity unofficial App for iPhone (https://furaffinity.app/)")
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
