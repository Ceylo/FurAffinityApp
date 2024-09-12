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
    @Entry var navigationStream: PassthroughSubject<FAURL, Never> = .init()
}

/// - Warning: This view should be avoided in scrolling content,
/// if it is likely to be touched during the scroll, as it'll display
/// a background style.
struct FALink<ContentView: View>: View {
    var destination: FAURL?
    var contentView: ContentView
    
    @Environment(\.navigationStream) private var navigationStream
    
    var body: some View {
        if let destination {
            Button {
                navigationStream.send(destination)
            } label: {
                contentView
            }
            // 🫠 https://forums.developer.apple.com/forums/thread/747558
            .buttonStyle(.borderless)
        } else {
            contentView
        }
    }
    
    init(destination: FAURL?, @ViewBuilder contentViewBuilder: () -> ContentView) {
        self.destination = destination
        self.contentView = contentViewBuilder()
    }
}

#Preview {
    NavigationStack {
        List {
            FALink(destination: .favorites(url: URL(string: "https://foo.com")!)) {
                SubmissionFeedItemView<AuthoredHeaderView>(submission: FASubmissionPreview.demo)
                    .border(.primary)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            
            NavigationLink(value: 42) {
                SubmissionFeedItemView<AuthoredHeaderView>(submission: FASubmissionPreview.demo)
                    .border(.primary)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
        .listStyle(.plain)
    }
    .environmentObject(Model.demo)
}
