//
//  RemoteContentToolbarItem.swift
//  FurAffinity
//
//  Created by Ceylo on 20/04/2025.
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
