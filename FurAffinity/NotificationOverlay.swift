//
//  NotificationOverlay.swift
//  FurAffinity
//
//  Created by Ceylo on 07/01/2022.
//

import SwiftUI

extension AnyTransition {
    static var fallAndFade: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
        )
    }
}


struct NotificationOverlay: View {
    @Binding var itemCount: Int?
    var dismissAfter: TimeInterval = 3.0
    
    func badge(_ count: Int) -> some View {
        Text("\(count) new submissions")
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.thinMaterial)
            .cornerRadius(15)
            .shadow(color: .black.opacity(0.5) , radius: 5, x: 0, y: 0)
    }
    
    var body: some View {
        if let itemCount = itemCount {
            badge(itemCount)
                .task {
                    do {
                        let nano = UInt64(dismissAfter * 1e9)
                        try await Task.sleep(nanoseconds: nano)
                        withAnimation {
                            self.itemCount = nil
                        }
                    } catch {}
                }
                .transition(.fallAndFade)
        }
    }
}

struct NotificationOverlay_Previews: PreviewProvider {
    static var previews: some View {
        NotificationOverlay(itemCount: .constant(12))
            .padding()
            .background(.blue)
            .previewLayout(.sizeThatFits)
    }
}
