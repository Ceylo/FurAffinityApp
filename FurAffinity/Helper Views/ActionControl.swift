//
//  ActionControl.swift
//  FurAffinity
//
//  Created by Ceylo on 08/05/2023.
//

import SwiftUI

struct ActionControl: View {
    private var _opaque: Bool = false
    
    func opaque(_ opaque: Bool = true) -> some View {
        var copy = self
        copy._opaque = opaque
        return copy
    }
    
    var body: some View {
        if #available(iOS 26, *), !_opaque {
            Image(systemName: "ellipsis")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
        } else {
            Image(systemName: "ellipsis")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 18, height: 18)
                .foregroundColor(.accentColor)
                .padding(5)
                .background(.thinMaterial)
                .clipShape(Circle())
                .padding(5)
        }
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
