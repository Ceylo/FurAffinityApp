//
//  SectionHeader.swift
//  FurAffinity
//
//  Created by Ceylo on 01/05/2024.
//

import SwiftUI

struct SectionHeader: View {
    var text: String
    var font: Font = .headline
    var verticalInset: Double = 5
    
    var body: some View {
        HStack {
            Text(text)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .applying {
            if #available(iOS 26, *) {
                $0
                    .padding(.vertical, verticalInset)
                    .glassEffect(in: .rect)
            } else {
                $0
            }
        }
        .font(font)
    }
}

#Preview {
    SectionHeader(text: "Section Header")
}
