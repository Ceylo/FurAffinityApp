//
//  View+scrollToItem.swift
//  FurAffinity
//
//  Created by Ceylo on 25/01/2025.
//

import SwiftUI

private struct ScrollToItemModifier<ID: Hashable>: ViewModifier {
    var targetId: ID?
    
    func body(content: Content) -> some View {
        ScrollViewReader { reader in
            content.onFirstAppear {
                if let targetId {
                    Task {
                        withAnimation {
                            reader.scrollTo(targetId, anchor: .center)
                        }
                    }
                }
            }
        }
    }
}

extension View {
    func scrollToItem(id: (some Hashable)?) -> some View {
        modifier(ScrollToItemModifier(targetId: id))
    }
}

