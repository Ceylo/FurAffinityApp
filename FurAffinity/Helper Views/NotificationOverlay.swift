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
        Text(count > 0 ? "\(count) new submissions" : "No new submission")
            .font(.callout)
            .foregroundColor(Color.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.thinMaterial)
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.33) , radius: 5, x: 0, y: 0)
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
            .background(.yellow)
            .previewLayout(.sizeThatFits)
    }
}
