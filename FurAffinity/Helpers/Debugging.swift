//
//  Debugging.swift
//  FurAffinity
//
//  Created by Ceylo on 17/11/2021.
//

import SwiftUI

struct Tracker: View {
    static var counter = 0
    var name: String
    
    var body: some View {
        Rectangle()
            .opacity(0)
            .frame(width: 0, height: 0)
            .onAppear {
                Self.counter += 1
                Swift.print("+", Self.counter, name)
            }
            .onDisappear {
                Self.counter -= 1
                Swift.print("-", Self.counter, name)
            }
    }
}

extension View {
    func Print(_ vars: Any...) -> some View {
        Swift.print(vars)
        return self
    }
}

