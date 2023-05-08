//
//  ActionControl.swift
//  FurAffinity
//
//  Created by Ceylo on 08/05/2023.
//

import SwiftUI

struct ActionControl: View {
    var body: some View {
        Text("…")
            .font(.headline)
            .foregroundColor(.primary)
            .padding(7.5)
            .offset(y: -4)
            .background(.thinMaterial)
            .clipShape(Circle())
    }
}

struct ActionControl_Previews: PreviewProvider {
    static var previews: some View {
        ActionControl()
    }
}
