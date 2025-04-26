//
//  UserNameView.swift
//  FurAffinity
//
//  Created by Ceylo on 26/04/2025.
//


import SwiftUI
import FAKit

struct UserNameView: View {
    init(name: String, displayName: String) {
        self.name = name
        self.displayName = displayName
    }
    
    var name: String
    var displayName: String
    
    enum DisplayStyle: CaseIterable {
        case compactRegularSize
        case compact
        case compactHighlightedDisplayName
        case multiline
        case multilineProminent
    }
    
    private var _displayStyle: DisplayStyle = .compact
    func displayStyle(_ style: DisplayStyle) -> Self {
        var copy = self
        copy._displayStyle = style
        return copy
    }
    
    var body: some View {
        switch _displayStyle {
        case .compactRegularSize:
            Text(displayName)
            +
            Text(" @\(name)")
                .foregroundStyle(.secondary)
        case .compact:
            Group {
                Text(displayName)
                +
                Text(" @\(name)")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        case .compactHighlightedDisplayName:
            Group {
                Text(displayName)
                    .bold()
                +
                Text(" @\(name)")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        case .multiline:
            VStack(alignment: .leading) {
                Text(displayName)
                    .font(.headline)
                Text("@\(name)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            
        case .multilineProminent:
            VStack(alignment: .leading) {
                Text(displayName)
                    .font(.largeTitle)
                    .bold()
                Text("@\(name)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    List {
        ForEach(UserNameView.DisplayStyle.allCases, id: \.hashValue) { displayStyle in
            
            HStack {
                Text("\(displayStyle)")
                    .font(.caption)
                Spacer()
                
                UserNameView(
                    name: "someuser",
                    displayName: "Some User"
                )
                .displayStyle(displayStyle)
                .border(.tertiary)
            }
        }
    }
    .listStyle(.plain)
}
