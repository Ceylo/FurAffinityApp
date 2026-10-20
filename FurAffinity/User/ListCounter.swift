//
//  ListCounter.swift
//  FurAffinity
//
//  Created by Ceylo on 03/11/2024.
//

import SwiftUI

struct ListCounter<T>: View {
    var name: String
    var fullList: [T]
    var filteredList: [T]
    
    private var countMessage: String {
        let filteredCount = filteredList.count
        if filteredCount != fullList.count {
            return "\(filteredCount) out of \(fullList.count) \(name)"  + plural(fullList.count)
        } else {
            return "\(fullList.count) \(name)" + plural(fullList.count)
        }
    }
    
    private func plural(_ value: Int) -> String {
        value > 1 ? "s" : ""
    }
    
    var body: some View {
        Section {
        } header: {
            HStack {
                Spacer()
                Text(countMessage)
                Spacer()
            }
        }
    }
}

#Preview {
    ListCounter(name: "user", fullList: [1, 2, 3], filteredList: [3])
    ListCounter(name: "user", fullList: [1, 2, 3], filteredList: [1, 2, 3])
    ListCounter(name: "user", fullList: [3], filteredList: [])
    ListCounter(name: "user", fullList: [3], filteredList: [3])
}
