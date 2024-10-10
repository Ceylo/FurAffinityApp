//
//  View.swift
//  FurAffinity
//
//  Created by Ceylo on 09/10/2024.
//

import SwiftUI

extension View {
    func apply<V: View>(@ViewBuilder _ closure: (Self) -> V) -> V {
        closure(self)
    }
}
