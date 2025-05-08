//
//  WatchControlStyle.swift
//  FurAffinity
//
//  Created by Ceylo on 01/05/2025.
//

import SwiftUI
import FAKit

struct WatchButton: View {
    var watchData: FAUser.WatchData?
    var toggleWatchAction: () async -> Void
    
    private var title: String {
        (watchData?.watching ?? false) ? "Unwatch" : "Watch"
    }
    
    private var systemImage: String {
        (watchData?.watching ?? false) ? "bookmark.fill": "bookmark"
    }
    
    
    var body: some View {
        Button {
            Task {
                await toggleWatchAction()
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
        // 🫠 https://forums.developer.apple.com/forums/thread/747558
        .buttonStyle(BorderlessButtonStyle())
        .sensoryFeedback(.impact, trigger: watchData?.watching, condition: {
            $1 == true
        })
    }
}

#Preview {
    WatchButton(watchData: nil) {
        
    }
}
