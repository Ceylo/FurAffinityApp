//
//  ActionControl.swift
//  FurAffinity
//
//  Created by Ceylo on 08/05/2023.
//

import SwiftUI

struct ActionControl: View {
    var body: some View {
        Image(systemName: "ellipsis")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 18, height: 18)
            .foregroundColor(.accentColor)
            .padding(5)
            .background(.thinMaterial)
            .clipShape(Circle())
    }
}

#Preview {
    NavigationStack {
        Text("")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        
                    } label: {
                        ActionControl()
                    }
                }
            }
    }
}
