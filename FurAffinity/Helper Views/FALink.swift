//
//  FALink.swift
//  FurAffinity
//
//  Created by Ceylo on 04/09/2024.
//


import SwiftUI
import Combine
import FAKit

extension EnvironmentValues {
    @Entry var navigationStream: PassthroughSubject<FATarget, Never> = .init()
}

/// - Warning: This view should be avoided in scrolling content,
/// if it is likely to be touched during the scroll, as it'll display
/// a background style.
struct FALink<ContentView: View>: View {
    var target: FATarget?
    var contentView: ContentView
    
    @Environment(\.navigationStream) private var navigationStream
    
    var body: some View {
        if let target {
            Button {
                navigationStream.send(target)
            } label: {
                contentView
            }
            // 🫠 https://forums.developer.apple.com/forums/thread/747558
            .buttonStyle(.borderless)
        } else {
            contentView
        }
    }
    
    init(destination: FATarget?, @ViewBuilder contentViewBuilder: () -> ContentView) {
        self.target = destination
        self.contentView = contentViewBuilder()
    }
}

#Preview {
    withAsync({ try await Model.demo }) {
        NavigationStack {
            List {
                FALink(destination: .favorites(url: URL(string: "https://foo.com")!)) {
                    SubmissionFeedItemView<TitleAuthorHeader>(submission: FASubmissionPreview.demo)
                        .border(.primary)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                
                NavigationLink(value: 42) {
                    SubmissionFeedItemView<TitleAuthorHeader>(submission: FASubmissionPreview.demo)
                        .border(.primary)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            .listStyle(.plain)
        }
        .environmentObject($0)
    }
}
