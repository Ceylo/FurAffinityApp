//
//  UserNameView.swift
//  FurAffinityUI (Android)
//
//  Android counterpart of the iOS `UserNameView`. Same name, same `DisplayStyle` cases
//  and the same `displayStyle(_:)`/`label(_:)` chaining, so callers symlink verbatim.
//
//  It can't be shared because the compact styles concatenate `Text + Text` to get one
//  wrapping paragraph with two styles, and `Text.+` is `@available(*, unavailable)` in
//  SkipSwiftUI. An `HStack(spacing: 0)` gives the same appearance for these short,
//  single-line labels; it just can't wrap between the two runs.
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
        case prominent
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
            case .prominent:
                ""
            }
        }
    }

    var body: some View {
        switch _displayStyle {
        case .compactRegularSize:
            HStack(spacing: 0) {
                Text(displayName)
                Text(usernameText)
                    .foregroundStyle(.secondary)
            }
        case .compact:
            HStack(spacing: 0) {
                Text(displayName)
                Text(usernameText)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
        case .compactHighlightedDisplayName:
            HStack(spacing: 0) {
                Text(displayName)
                    .bold()
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
        case .prominent:
            Text(displayName)
                .font(.largeTitle)
        }
    }
}
