//
//  AlignedLabel.swift
//  FurAffinity
//
//  Created by Ceylo on 19/08/2024.
//

import SwiftUI

extension View {
    /// An optical nudge tuned for SF Symbols. Material icons centre their glyph in
    /// the box, so on Android the nudge only misaligns them.
    func symbolOpticalOffset(y: CGFloat) -> some View {
        #if FA_SKIP_MODULE
        self
        #else
        offset(y: y)
        #endif
    }
}

#if FA_SKIP_MODULE
/// Material's `title3` line height pads below the digits, so `.bottom` drops them.
private let labelAlignment = VerticalAlignment.center
#else
private let labelAlignment = VerticalAlignment.bottom
#endif

struct AlignedLabel: View {
    var value: Int
    var systemImage: String
    var imageYOffset = 0.0

    var body: some View {
        HStack(alignment: labelAlignment, spacing: 5) {
            if value > 0 {
                Text("\(value)")
                    .font(.title3)
            }
            Image(systemName: systemImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .symbolOpticalOffset(y: imageYOffset)
        }
        .padding()
        .symbolOpticalOffset(y: value > 0 ? 3 : 5.5)
    }
}
