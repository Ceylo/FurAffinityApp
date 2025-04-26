//
//  CommentView.swift
//  FurAffinity
//
//  Created by Ceylo on 23/04/2023.
//

import SwiftUI
import FAKit

struct CommentView: View {
    var comment: FAComment
    var highlight: Bool
    @Environment(\.colorScheme) var colorScheme
    private let avatarSize = 42.0
    @State private var rowBackgroundAnimated = false
    
    var overlayStyle: some ShapeStyle {
        switch colorScheme {
        case .light:
            HierarchicalShapeStyle.secondary.opacity(0.15)
        case .dark:
            HierarchicalShapeStyle.secondary.opacity(0.25)
        @unknown default:
            fatalError()
        }
    }
    
    var textBubble: some View {
        HTMLView(
            text: comment.message.convertingLinksForInAppNavigation(),
            initialHeight: 32
        )
        .padding(.horizontal, 1)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(overlayStyle)
        }
    }
    
    func userFATarget(for comment: FAVisibleComment) -> FATarget? {
        guard let userUrl = FAURLs.userpageUrl(for: comment.author) else {
            return nil
        }
        
        return .user(
            url: userUrl,
            previewData: .init(
                username: comment.author,
                displayName: comment.displayAuthor,
                avatarUrl: FAURLs.avatarUrl(for: comment.author)
            )
        )
    }
    
    func commentView(_ comment: FAVisibleComment) -> some View {
        HStack(alignment: .top) {
            FALink(destination: userFATarget(for: comment)) {
                AvatarView(avatarUrl: FAURLs.avatarUrl(for: comment.author))
                    .frame(width: avatarSize, height: avatarSize)
            }
            
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    UserNameView(
                        name: comment.author,
                        displayName: comment.displayAuthor
                    )
                    .displayStyle(.compactHighlightedDisplayName)
                    Spacer()
                    DateTimeButton(datetime: comment.datetime,
                                   naturalDatetime: comment.naturalDatetime)
                }
                textBubble
            }
        }
    }
    
    func commentView(_ comment: FAHiddenComment) -> some View {
        HStack(alignment: .top) {
            AvatarView(avatarUrl: nil)
                .frame(width: avatarSize, height: avatarSize)
                .padding(.top, 5)
            
            textBubble
        }
    }
    
    @ViewBuilder
    private var rowBackground: some View {
        if highlight {
            (rowBackgroundAnimated ? Color.primary.opacity(0) : Color.primary.opacity(0.15))
                .animation(
                    .easeInOut
                        .speed(0.333)
                        .repeatCount(5, autoreverses: true)
                )
        }
    }
    
    var body: some View {
        Group {
            switch comment {
            case let .visible(comment):
                commentView(comment)
            case let .hidden(comment):
                commentView(comment)
            }
        }
        .listRowBackground(rowBackground)
        .onAppear {
            // According to https://stackoverflow.com/a/66391586/869385
            // animation on list row background has to be triggered
            // asynchronously
            Task {
                rowBackgroundAnimated = true
            }
        }
        .id(comment.id)
    }
}

#Preview("Visible comment") {
    withAsync({ await FAComment.demo[0] }) { comment in
        NavigationStack {
            List {
                CommentView(comment: comment, highlight: true)
            }
            .listStyle(.plain)
        }
    }
}

#Preview("Hidden comment") {
    withAsync({ await FAComment.demoHidden[0] }) { comment in
        NavigationStack {
            List {
                CommentView(comment: comment, highlight: false)
            }
            .listStyle(.plain)
        }
    }
}
