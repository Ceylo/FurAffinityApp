//
//  RemoteContentToolbarItem.swift
//  FurAffinity
//
//  Created by Ceylo on 20/04/2025.
//

import SwiftUI

struct RemoteContentToolbarItem<ContentsView: View>: ToolbarContent {
    init(url: URL, @ViewBuilder additionalToolbarItems: @escaping () -> ContentsView = { EmptyView() }) {
        self.url = url
        self.additionalToolbarItems = additionalToolbarItems
    }
    
    var url: URL
    var additionalToolbarItems: () -> ContentsView
    
    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Link(destination: url) {
                    Label("Open in Web Browser", systemImage: "safari")
                }
                ShareLink(
                    item: url,
                    message: Text("Sent from the unofficial FurAffinity App for iPhone (https://furaffinity.app/)")
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
