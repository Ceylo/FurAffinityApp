//
//  View+applying.swift
//  FurAffinity
//
//  Created by Ceylo on 18/07/2025.
//

import SwiftUI

extension View {
    func applying(@ViewBuilder _ closure: (Self) -> some View) -> some View {
        closure(self)
    }
}
