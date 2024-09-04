//
//  OptionalLink.swift
//  FurAffinity
//
//  Created by Ceylo on 19/03/2023.
//

import SwiftUI

struct OptionalLink<Wrapped: View>: View {
    var destination: URL?
    @ViewBuilder
    var subview: () -> Wrapped
    
    var body: some View {
        if let destination {
            Link(destination: destination) {
                subview()
            }
            // 🫠 https://forums.developer.apple.com/forums/thread/747558
            .buttonStyle(BorderlessButtonStyle())
        } else {
            subview()
        }
    }
}
