//
//  RemoteView.swift
//  FurAffinity
//
//  Created by Ceylo on 19/11/2023.
//

import SwiftUI

protocol UpdateHandler<Contents> {
    associatedtype Contents: Sendable
    
    @MainActor
    func update(with contents: Contents?)
}

/// `PreviewableRemoteView` provides common behavior for remotely loaded content, such as:
/// - displaying a progress until content becomes available
/// - displaying a incomplete view until the content is loaded
/// - allowing pull to refresh
/// - giving web access to the content
struct PreviewableRemoteView<Contents: Sendable, ContentsView: View, PreviewView: View>: View, UpdateHandler {
    init(
        url: URL,
        contentsLoader: @escaping () async -> Contents?,
        @ViewBuilder previewViewBuilder: @escaping () -> PreviewView? = { nil }, contentsViewBuilder:
        @escaping (Contents, any UpdateHandler<Contents>) -> ContentsView
    ) {
        self.url = url
        self.contentsLoader = contentsLoader
        self.previewViewBuilder = previewViewBuilder
        self.contentsViewBuilder = contentsViewBuilder
    }
    
    var url: URL
    var contentsLoader: () async -> Contents?
    @ViewBuilder var previewViewBuilder: () -> PreviewView?
    var contentsViewBuilder: (
        _ contents: Contents,
        _ updateHandler: any UpdateHandler<Contents>
    ) -> ContentsView
    
    private enum ContentsState {
        case loaded(Contents)
        case failed
    }
    @State private var contentsState: ContentsState?
    
    var body: some View {
        Group {
            if let contentsState {
                switch contentsState {
                case .loaded(let contents):
                    contentsViewBuilder(contents, self)
                case .failed:
                    ScrollView {
                        LoadingFailedView(url: url)
                    }
                }
            } else {
                if let preview = previewViewBuilder() {
                    preview
                } else {
                    VStack(spacing: 20) {
                        ProgressView()
                        Link("Waiting for \(url.host(percentEncoded: false) ?? "?")…", destination: url)
                    }
                }
            }
        }
        .task {
            if contentsState == nil {
                await update()
            }
        }
        .refreshable {
            await update()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Link(destination: url) {
                    Image(systemName: "safari")
                }
            }
        }
    }
    
    func update() async {
        let contents = await contentsLoader()
        update(with: contents)
    }

    func update(with contents: Contents?) {
        if let contents {
            self.contentsState = .loaded(contents)
        } else {
            self.contentsState = .failed
        }
    }
}

typealias RemoteView<Contents: Sendable, ContentsView: View> = PreviewableRemoteView<Contents, ContentsView, EmptyView>
