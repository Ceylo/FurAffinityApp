//
//  AlignedLabel.swift
//  FurAffinity
//
//  Created by Ceylo on 19/08/2024.
//

import SwiftUI

struct AlignedLabel: View {
    var value: Int
    var systemImage: String
    var imageYOffset = 0.0
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            if value > 0 {
                Text("\(value)")
                    .font(.title3)
            }
            Image(systemName: systemImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .offset(y: imageYOffset)
        }
        .padding()
        .offset(y: value > 0 ? 3 : 5.5)
    }
}
