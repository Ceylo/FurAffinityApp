//
//  WatchingPill.swift
//  FurAffinity
//
//  Created by Ceylo on 08/05/2025.
//

import SwiftUI

struct WatchingPill: View {
    var body: some View {
        Text("Watching")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(5)
            .padding(.horizontal, 5)
            .background {
                RoundedRectangle(cornerRadius: 15)
                    .fill(.secondary.opacity(0.3))
            }
            .padding(-5)
    }
}

#Preview {
    WatchingPill()
}
