//
//  FALink.swift
//  FurAffinity
//
//  Created by Ceylo on 04/09/2024.
//


import SwiftUI
import FAKit

/// One-way channel from tappable links to the navigation host.
///
/// Events carry a monotonic ID because `FATarget` is `Hashable`: without it, an
/// `.onChange` observer would silently drop two identical consecutive navigations.
@Observable @MainActor
final class NavigationStream {
    struct Event: Equatable {
        let target: FATarget
        let id: Int
    }

    private(set) var latest: Event?
    private var nextID = 0

    /// Nonisolated so `EnvironmentValues`' nonisolated `defaultValue` can build one.
    nonisolated init() {}

    func send(_ target: FATarget) {
        nextID += 1
        latest = .init(target: target, id: nextID)
    }
}

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
