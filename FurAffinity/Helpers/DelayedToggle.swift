//
//  DelayedToggle.swift
//  FurAffinity
//
//  Created by Ceylo on 29/12/2024.
//


import SwiftUI

struct DelayedToggle: ViewModifier {
    @Binding var toggle: Bool
    var delay: Duration
    @State private var task: Task<(), Error>?
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                task?.cancel()
                task = Task {
                    try await Task.sleep(for: delay)
                    withAnimation {
                        toggle = true
                    }
                }
            }
            .onDisappear {
                task?.cancel()
                toggle = false
            }
    }
}
