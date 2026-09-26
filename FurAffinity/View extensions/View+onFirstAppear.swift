//
//  OnFirstAppearModifier.swift
//  FurAffinity
//
//  Created by Ceylo on 18/01/2025.
//  From https://holyswift.app/triggering-an-action-only-first-time-a-view-appears-in-swiftui/
//

import SwiftUI

// Not private: skipstone doesn't bridge a private type.
struct OnFirstAppearModifier: ViewModifier {

    private let onFirstAppearAction: () -> ()
    // Not private: skipstone can't bridge a private @State.
    @State var hasAppeared = false
    
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
