//
//  SectionHeader.swift
//  FurAffinity
//
//  Created by Ceylo on 01/05/2024.
//

import SwiftUI

struct SectionHeader: View {
    var text: String
    
    var body: some View {
        HStack {
            Text(text)
                .font(.headline)
            Spacer()
        }
        .padding(10)
    }
}

#if !FA_SKIP_MODULE
#Preview {
    SectionHeader(text: "Section Header")
}
#endif
