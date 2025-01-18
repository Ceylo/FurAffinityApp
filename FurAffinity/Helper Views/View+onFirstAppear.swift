//
//  OnFirstAppearModifier.swift
//  FurAffinity
//
//  Created by Ceylo on 18/01/2025.
//  From https://holyswift.app/triggering-an-action-only-first-time-a-view-appears-in-swiftui/
//

import SwiftUI

public struct OnFirstAppearModifier: ViewModifier {

    private let onFirstAppearAction: () -> ()
    @State private var hasAppeared = false
    
    public init(_ onFirstAppearAction: @escaping () -> ()) {
        self.onFirstAppearAction = onFirstAppearAction
    }
    
    public func body(content: Content) -> some View {
        content
            .onAppear {
                guard !hasAppeared else { return }
                hasAppeared = true
                onFirstAppearAction()
            }
    }
}

extension View {
    func onFirstAppear(_ onFirstAppearAction: @escaping () -> () ) -> some View {
        modifier(OnFirstAppearModifier(onFirstAppearAction))
    }
}
