//
//  TagSearchEditor.swift
//  FurAffinity
//
//  Created by Ceylo on 02/07/2026.
//

import SwiftUI
import WrappingHStack
import OrderedCollections

/// A chip-based editor for tag-scoped search criteria. Unlike the free-text bar
/// (which searches everywhere in a submission's metadata), these tags search a
/// submission's **tags only** via FA's `@keywords` operator. Included tags must
/// be present; excluded tags must not (`!tag`).
///
/// Tapping a chip toggles it between included and excluded. The trailing "Add
/// tag" affordance opens an inline field; a leading `!` (e.g. `!bird`) adds an
/// excluded chip, otherwise an included one.
struct TagSearchEditor: View {
    @Binding var includedTags: OrderedSet<String>
    @Binding var excludedTags: OrderedSet<String>

    @State private var isAddingTag = false
    @State private var newTagText = ""
    @FocusState private var addFieldFocused: Bool

    /// One laid-out element of the chip zone. Flattening the tags and the add
    /// control into a single collection lets `WrappingHStack`'s collection-based
    /// initializer measure and wrap each element individually — its ViewBuilder
    /// initializer treats a `ForEach` as one non-wrapping unit instead.
    private enum ChipItem: Hashable {
        case included(String)
        case excluded(String)
        case addControl
    }

    private var chipItems: [ChipItem] {
        includedTags.map(ChipItem.included)
            + excludedTags.map(ChipItem.excluded)
            + [.addControl]
    }

    /// Normalizes user input into a tag token, or nil if it's empty. FA tags
    /// contain no spaces and are case-insensitive.
    private static func normalize(_ raw: String) -> String? {
        let trimmed = raw
            .trimmingCharacters(in: .whitespaces)
            .drop(while: { $0 == "!" })
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    private func moveToExcluded(_ tag: String) {
        includedTags.remove(tag)
        if !excludedTags.contains(tag) { excludedTags.append(tag) }
    }

    private func moveToIncluded(_ tag: String) {
        excludedTags.remove(tag)
        if !includedTags.contains(tag) { includedTags.append(tag) }
    }

    private func remove(_ tag: String) {
        includedTags.remove(tag)
        excludedTags.remove(tag)
    }

    /// Adds one token to the appropriate array. A leading `!` (e.g. `!bird`)
    /// marks it excluded; otherwise included. Normalizes and de-dupes across
    /// both arrays.
    private func addToken(_ raw: String) {
        let excluded = raw.trimmingCharacters(in: .whitespaces).hasPrefix("!")
        guard let tag = Self.normalize(raw) else { return }
        remove(tag)
        if excluded {
            excludedTags.append(tag)
        } else {
            includedTags.append(tag)
        }
    }

    /// Turns whitespace-separated input into individual chips as the user types.
    /// Complete tokens (all but a trailing partial word) are committed; the
    /// partial stays in the field. A trailing space commits every token.
    private func tokenizeIfNeeded(_ text: String) {
        guard text.contains(where: \.isWhitespace) else { return }
        var tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let remainder = (text.last?.isWhitespace ?? false) ? "" : (tokens.popLast() ?? "")
        for token in tokens { addToken(token) }
        newTagText = remainder
    }

    private func commitNewTag() {
        for token in newTagText.split(whereSeparator: \.isWhitespace).map(String.init) {
            addToken(token)
        }
        newTagText = ""
        // Keep the field open for quick multi-tag entry.
        addFieldFocused = true
    }

    private func includedChip(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "tag")
                .font(.caption2)
            Text(tag)
                .lineLimit(1)
                .fixedSize()
                .onTapGesture { moveToExcluded(tag) }
            Button {
                remove(tag)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            // 🫠 https://forums.developer.apple.com/forums/thread/747558
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(Color.accentColor.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        
    }

    private func excludedChip(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "minus.circle")
                .font(.caption2)
            Text(tag)
                .strikethrough()
                .lineLimit(1)
                .fixedSize()
                .onTapGesture { moveToIncluded(tag) }
            Button {
                remove(tag)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            // 🫠 https://forums.developer.apple.com/forums/thread/747558
            .buttonStyle(.borderless)
        }
        .foregroundStyle(.red)
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(Color.red.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        
    }

    private var addTagControl: some View {
        Group {
            if isAddingTag {
                TextField("tag", text: $newTagText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($addFieldFocused)
                    .frame(minWidth: 60)
                    .onSubmit { commitNewTag() }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                Button {
                    isAddingTag = true
                    addFieldFocused = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add tag")
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4]))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    var body: some View {
        WrappingHStack(
            chipItems,
            id: \.self,
            spacing: .constant(6),
            lineSpacing: 6
        ) { item in
            switch item {
            case .included(let tag): includedChip(tag)
            case .excluded(let tag): excludedChip(tag)
            case .addControl: addTagControl
            }
        }
        .onChange(of: newTagText) { _, newValue in
            tokenizeIfNeeded(newValue)
        }
        .onChange(of: isAddingTag) { _, adding in
            if !adding { newTagText = "" }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var included: OrderedSet = ["wolf", "forest", "digital", "landscape", "nighttime"]
        @State var excluded: OrderedSet = ["bird", "watermark"]
        var body: some View {
            Form {
                Section {
                    TagSearchEditor(includedTags: $included, excludedTags: $excluded)
                } header: {
                    Text("Tags")
                } footer: {
                    Text("Searched in submission tags only.")
                }
            }
        }
    }
    return PreviewWrapper()
}
