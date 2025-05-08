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
    
    private var _label: AnyView?
    func label(@ViewBuilder _ view: () -> some View) -> Self {
        var copy = self
        copy._label = AnyView(view())
        return copy
    }
    
    private var usernameText: String {
        if name.isEmpty {
            ""
        } else {
            switch _displayStyle {
            case .compactRegularSize, .compact, .compactHighlightedDisplayName:
                " @\(name)"
            case .multiline, .multilineProminent:
                "@\(name)"
            }
        }
    }
    
    var body: some View {
        switch _displayStyle {
        case .compactRegularSize:
            Text(displayName)
            +
            Text(usernameText)
                .foregroundStyle(.secondary)
        case .compact:
            Group {
                Text(displayName)
                +
                Text(usernameText)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        case .compactHighlightedDisplayName:
            Group {
                Text(displayName)
                    .bold()
                +
                Text(usernameText)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        case .multiline:
            VStack(alignment: .leading) {
                Text(displayName)
                    .font(.headline)
                Text(usernameText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            
        case .multilineProminent:
            VStack(alignment: .leading, spacing: 5) {
                Text(displayName)
                    .font(.largeTitle)
                    .bold()
                HStack {
                    Text(usernameText)
                        .foregroundStyle(.secondary)
                    
                    if let _label {
                        Spacer()
                        _label
                    }
                }
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
                .label {
                    WatchingPill()
                }
                .border(.tertiary)
            }
        }
    }
    .listStyle(.plain)
}
