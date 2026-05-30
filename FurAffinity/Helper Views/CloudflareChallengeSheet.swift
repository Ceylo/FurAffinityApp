//
//  CloudflareChallengeSheet.swift
//  FurAffinity
//
//  Created by Ceylo on 27/05/2026.
//


import SwiftUI
import FAKit
import AmplitudeSwift

struct CloudflareChallengeSheet: View {
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("CloudFlare check required")
                    .font(.title)
                Text("furaffinity.net is asking you to confirm you're human. Complete the check below to continue.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding()

            FAChallengeView(onResolved: {
                CloudflareChallengeCoordinator.shared.markResolved()
            })
        }
    }
}

#Preview {
    CloudflareChallengeSheet()
}
