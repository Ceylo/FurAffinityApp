//
//  AppIcon.swift
//  FurAffinity
//
//  Created by Ceylo on 01/09/2024.
//

import SwiftUI

struct AppIcon: View {
    var body: some View {
        Image("AppIcon")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 100)
            .cornerRadius(10)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.borderOverlay, lineWidth: 1)
            }
    }
}


#Preview {
    AppIcon()
}
