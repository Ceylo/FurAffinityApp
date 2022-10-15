//
//  SwapView.swift
//  FurAffinity
//
//  Created by Ceylo on 15/10/2022.
//

import SwiftUI

struct SwapView: ViewModifier {
    let condition: Bool
    let placeholder: AnyView
    func body(content: Content) -> some View {
        if condition {
            placeholder
        } else {
            content
        }
    }
}

//MARK: View Extension
extension View {
    func swap(when condition: Bool, @ViewBuilder with view: () -> some View) -> some View {
        self.modifier(SwapView(condition: condition, placeholder: AnyView(view())))
    }
}
