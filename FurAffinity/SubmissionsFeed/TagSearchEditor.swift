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
/// Tags share a single ordered set: an excluded tag is stored with a leading `!`
/// (e.g. `!bird`), so toggling include/exclude is an in-place prefix flip that
/// preserves the chip's position. Tapping a chip toggles it; the trailing "Add
/// tag" affordance opens an inline field where a leading `!` adds an excluded chip.
struct TagSearchEditor: View {
    @Binding var tags: OrderedSet<String>

    @State private var isAddingTag = false
    @State private var newTagText = ""
    @FocusState private var addFieldFocused: Bool

    /// One laid-out element of the chip zone. Flattening the tags and the add
    /// control into a single collection lets `WrappingHStack`'s collection-based
    /// initializer measure and wrap each element individually — its ViewBuilder
    /// initializer treats a `ForEach` as one non-wrapping unit instead.
    private enum Item: Hashable {
        case tag(String)
        case addControl
    }

    private var chipItems: [Item] {
        tags.map(Item.tag) + (isAddingTag ? [] : [.addControl])
    }

    // MARK: - Token helpers

    private func isExcluded(_ token: String) -> Bool { token.hasPrefix("!") }

    /// The displayed tag text, without the `!` exclusion marker.
    private func label(_ token: String) -> String {
        isExcluded(token) ? String(token.dropFirst()) : token
    }

    /// Normalizes user input into a stored token, or nil if it has no base text.
    /// FA tags are case-insensitive and contain no spaces; a single leading `!`
    /// is preserved as the exclusion marker (extra `!`s are collapsed).
    private func normalizedToken(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let excluded = trimmed.hasPrefix("!")
        let base = trimmed
            .drop(while: { $0 == "!" })
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        guard !base.isEmpty else { return nil }
        return excluded ? "!" + base : base
    }

    /// Adds one token, de-duping both polarities of the same base tag so a tag
    /// can't appear twice (e.g. adding `bird` after `!bird` replaces it).
    private func addToken(_ raw: String) {
        guard let token = normalizedToken(raw) else { return }
        let base = label(token)
        tags.remove(base)
        tags.remove("!" + base)
        tags.append(token)
    }

    /// Flips a chip between included and excluded **in place**, keeping its slot
    /// in the ordered set so the chip doesn't jump.
    private func toggleExclusion(_ token: String) {
        guard let index = tags.firstIndex(of: token) else { return }
        let flipped = isExcluded(token) ? label(token) : "!" + token
        tags.remove(at: index)
        tags.insert(flipped, at: index)
    }

    private func remove(_ token: String) {
        tags.remove(token)
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

    /// Commits whatever is left in the field into chips and clears it.
    private func commitRemainder() {
        for token in newTagText.split(whereSeparator: \.isWhitespace).map(String.init) {
            addToken(token)
        }
        newTagText = ""
    }

    private func commitNewTag() {
        commitRemainder()
        // Keep the field open for quick multi-tag entry.
        addFieldFocused = true
    }

    // MARK: - Views

    private func chip(_ token: String) -> some View {
        let excluded = isExcluded(token)
        return HStack(spacing: 4) {
            Image(systemName: excluded ? "minus.circle" : "tag")
                .font(.caption2)
            Text(label(token))
                .strikethrough(excluded)
                .lineLimit(1)
                .fixedSize()
                .onTapGesture { toggleExclusion(token) }
            Button {
                remove(token)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            // 🫠 https://forums.developer.apple.com/forums/thread/747558
            .buttonStyle(.borderless)
        }
        .foregroundStyle(excluded ? Color.red : Color.primary)
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background((excluded ? Color.red : Color.accentColor).opacity(excluded ? 0.15 : 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    private var addControl: some View {
        Button {
            withAnimation { isAddingTag = true }
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

    var body: some View {
        // A bare Group so the Form renders the chips and the add field as
        // separate rows — the field then gets a full-width, native row height.
        Group {
            if !isAddingTag || !tags.isEmpty {
                WrappingHStack(
                    chipItems,
                    id: \.self,
                    spacing: .constant(6),
                    lineSpacing: 6
                ) { item in
                    switch item {
                    case .tag(let token): chip(token)
                    case .addControl: addControl
                    }
                }
                .animation(.default.speed(2), value: tags)
            }

            if isAddingTag {
                TextField("tag", text: $newTagText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($addFieldFocused)
                    .onAppear { addFieldFocused = true }
                    .onChange(of: newTagText) { _, newValue in
                        tokenizeIfNeeded(newValue)
                    }
                    .onSubmit { commitNewTag() }
                    .onChange(of: addFieldFocused) { _, focused in
                        // Blur commits the remainder and collapses back to the button.
                        if !focused {
                            commitRemainder()
                            withAnimation { isAddingTag = false }
                        }
                    }
            }
        }
    }
}

#Preview {
    @Previewable
    @State var tags: OrderedSet = ["wolf", "forest", "!bird", "!watermark"]

    Form {
        Section {
            TagSearchEditor(tags: $tags)
        } header: {
            Text("Tags")
        } footer: {
            Text("Searched in submission tags only.")
        }
    }
}
