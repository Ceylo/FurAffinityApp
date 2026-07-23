//
//  FALink.swift
//  FurAffinity
//
//  Created by Ceylo on 04/09/2024.
//


import SwiftUI
import FAKit
#if !os(Android)
import Combine
#endif

#if os(Android)
/// Combine is unavailable on Android. This keeps `FALink`'s `send(_:)` call site
/// identical until in-app navigation is ported; taps are dropped for now.
final class NavigationStream: Sendable {
    func send(_ target: FATarget) {}
}
#else
typealias NavigationStream = PassthroughSubject<FATarget, Never>
#endif

// A hand-written EnvironmentKey rather than @Entry: SkipUI doesn't provide that macro.
private struct NavigationStreamKey: EnvironmentKey {
    static var defaultValue: NavigationStream { .init() }
}

extension EnvironmentValues {
    var navigationStream: NavigationStream {
        get { self[NavigationStreamKey.self] }
        set { self[NavigationStreamKey.self] = newValue }
    }
}

/// - Warning: This view should be avoided in scrolling content,
/// if it is likely to be touched during the scroll, as it'll display
/// a background style.
struct FALink<ContentView: View>: View {
    var target: FATarget?
    var contentView: ContentView
    
    private var fullWidthTapArea = false
    @Environment(\.navigationStream) var navigationStream
    
    func withFullWidthTapArea() -> Self {
        var copy = self
        copy.fullWidthTapArea = true
        return copy
    }
    
    var body: some View {
        if let target {
            Button {
                navigationStream.send(target)
            } label: {
                contentView
            }
            .applying {
                if fullWidthTapArea {
                    $0
                } else {
                    // 🫠 https://forums.developer.apple.com/forums/thread/747558
                    $0.buttonStyle(.borderless)
                }
            }
        } else {
            contentView
        }
    }
    
    init(destination: FATarget?, @ViewBuilder contentViewBuilder: () -> ContentView) {
        self.target = destination
        self.contentView = contentViewBuilder()
    }
}

#if !FA_SKIP_MODULE
#Preview {
    withAsync({ try await Model.demo }) {
        NavigationStack {
            List {
                FALink(destination: .favorites(url: URL(string: "https://foo.com")!)) {
                    SubmissionFeedItemView<TitleAuthorHeader>(submission: FASubmissionPreview.demo)
                        .border(.primary)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
            .listStyle(.plain)
            
            List {
                FALink(destination: .favorites(url: URL(string: "https://foo.com")!)) {
                    Text("foo bar")
                }
                .withFullWidthTapArea()
            }
        }
        .environment($0)
    }
}
#endif
