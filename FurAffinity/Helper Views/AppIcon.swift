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
            .frame(width: 150)
    }
}


#Preview {
    AppIcon()
}
