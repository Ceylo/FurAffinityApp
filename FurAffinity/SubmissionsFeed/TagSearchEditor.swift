//
//  TagSearchEditor.swift
//  FurAffinity
//
//  Created by Ceylo on 02/07/2026.
//

import SwiftUI
import WrappingHStack

/// A chip-based editor for tag-scoped search criteria. Unlike the free-text bar
/// (which searches everywhere in a submission's metadata), these tags search a
/// submission's **tags only** via FA's `@keywords` operator. Included tags must
/// be present; excluded tags must not (`!tag`).
///
/// Tapping a chip toggles it between included and excluded. The trailing "Add
/// tag" affordance opens an inline field; a leading `!` (e.g. `!bird`) adds an
/// excluded chip, otherwise an included one.
struct TagSearchEditor: View {
    @Binding var includedTags: [String]
    @Binding var excludedTags: [String]

    @State private var isAddingTag = false
    @State private var newTagText = ""
    @FocusState private var addFieldFocused: Bool

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
        includedTags.removeAll { $0 == tag }
        if !excludedTags.contains(tag) { excludedTags.append(tag) }
    }

    private func moveToIncluded(_ tag: String) {
        excludedTags.removeAll { $0 == tag }
        if !includedTags.contains(tag) { includedTags.append(tag) }
    }

    private func remove(_ tag: String) {
        includedTags.removeAll { $0 == tag }
        excludedTags.removeAll { $0 == tag }
    }

    private func commitNewTag() {
        let excluded = newTagText.trimmingCharacters(in: .whitespaces).hasPrefix("!")
        guard let tag = Self.normalize(newTagText) else {
            newTagText = ""
            isAddingTag = false
            return
        }
        remove(tag)
        if excluded {
            excludedTags.append(tag)
        } else {
            includedTags.append(tag)
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
            Button {
                remove(tag)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(Color.accentColor.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { moveToExcluded(tag) }
    }

    private func excludedChip(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "minus.circle")
                .font(.caption2)
            Text(tag)
                .strikethrough()
            Button {
                remove(tag)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.red)
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(Color.red.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { moveToIncluded(tag) }
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
        VStack(alignment: .leading, spacing: 6) {
            Text("Tags · searched in submission tags only")
                .font(.caption)
                .foregroundStyle(.secondary)

            WrappingHStack(
                alignment: .leading,
                spacing: .constant(6),
                lineSpacing: 6
            ) {
                ForEach(includedTags, id: \.self) { includedChip($0) }
                ForEach(excludedTags, id: \.self) { excludedChip($0) }
                addTagControl
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 4)
        .onChange(of: isAddingTag) { _, adding in
            if !adding { newTagText = "" }
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var included = ["wolf", "forest"]
        @State var excluded = ["bird"]
        var body: some View {
            TagSearchEditor(includedTags: $included, excludedTags: $excluded)
        }
    }
    return PreviewWrapper()
}
