//
//  AndroidRootView.swift
//  FurAffinityUI (Android)
//
//  Placeholder root. Step by step this is replaced by the shared HomeView /
//  LoggedInView the iOS app already uses.
//

import SwiftUI
import FAKit

struct AndroidRootView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Fur Affinity")
                .font(.largeTitle)
            Text("Android port — scaffolding")
                .foregroundStyle(.secondary)
        }
        .task {
            logger.info("Android root view appeared")
        }
    }
}
