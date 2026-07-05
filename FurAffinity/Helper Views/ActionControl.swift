//
//  ActionControl.swift
//  FurAffinity
//
//  Created by Ceylo on 08/05/2023.
//

import SwiftUI

struct ActionControl: View {
    private var _opaque: Bool = false
    private var size: Double = 24
    var systemImage: String = "ellipsis"

    init(systemImage: String = "ellipsis") {
        self.systemImage = systemImage
    }

    func opaque(_ opaque: Bool = true) -> some View {
        var copy = self
        copy._opaque = opaque
        return copy
    }

    var body: some View {
        if #available(iOS 26, *) {
            if _opaque {
                Image(systemName: systemImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .tint(.primary)
                    .frame(width: size, height: size)
                    .padding(10)
                    .offset(y: 1)
            } else {
                Image(systemName: systemImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
            }
        } else {
            Image(systemName: systemImage)
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
        // A floating control (opaque + glass, as in SubmissionsTabView) overlaid
        // at the top-trailing corner, next to the system-supplied toolbar button
        // of the same style — the two glass capsules should match in size.
        Color.clear
            .overlay(alignment: .topTrailing) {
                Button {} label: {
                    ActionControl(systemImage: "heart")
                        .opaque()
                }
                .applying { control in
                    if #available(iOS 26, *) {
                        GlassEffectContainer { control.glassEffect() }
                    } else {
                        control
                    }
                }
                .padding(.trailing, 16)
            }
            .toolbar {
                ToolbarItem {
                    Button {} label: {
                        ActionControl()
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                Rectangle()
                    .stroke(Color.red)
                    .frame(width: 44, height: 100)
                    .padding(.trailing, 16)
                    .offset(y: -54)
            }
    }
}
