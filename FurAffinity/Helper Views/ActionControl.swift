//
//  ActionControl.swift
//  FurAffinity
//
//  Created by Ceylo on 08/05/2023.
//

import SwiftUI

struct ActionControl: View {
    private var _opaque: Bool = false
    private var size: Double = 18
    
    func opaque(_ opaque: Bool = true) -> some View {
        var copy = self
        copy._opaque = opaque
        return copy
    }
    
    var body: some View {
        if #available(iOS 26, *) {
            if _opaque {
                Image(systemName: "ellipsis")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .tint(.primary)
                    .frame(width: size, height: size)
                    .padding(13)
                    .glassEffect()
            } else {
                Image(systemName: "ellipsis")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            }
        } else {
            Image(systemName: "ellipsis")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
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
        HStack {
            Spacer()
            
            Button {
                
            } label: {
                ActionControl()
                    .opaque()
            }
            .padding(.trailing, 16)
        }
        
        Spacer()
        
        Text("Hi")
            .toolbar {
                ToolbarItem {
                    Button {
                        
                    } label: {
                        ActionControl()
                    }
                }
            }
    }
}
