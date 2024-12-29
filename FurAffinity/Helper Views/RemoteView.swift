//
//  RemoteView.swift
//  FurAffinity
//
//  Created by Ceylo on 19/11/2023.
//

import SwiftUI

protocol UpdateHandler<Data> {
    associatedtype Data: Sendable
    
    @MainActor
    func update(with data: Data?)
}

/// `PreviewableRemoteView` provides common behavior for remotely loaded content, such as:
/// - displaying a progress until content becomes available
/// - displaying a incomplete view until the content is loaded
/// - allowing pull to refresh
/// - giving web access to the content
struct PreviewableRemoteView<Data: Sendable, ContentsView: View, PreviewView: View>: View, UpdateHandler {
    init(
        url: URL,
        dataSource: @escaping (_ sourceUrl: URL) async -> Data?,
        @ViewBuilder preview: @escaping () -> PreviewView? = { nil },
        view: @escaping (Data, any UpdateHandler<Data>) -> ContentsView
    ) {
        self.url = url
        self.dataSource = dataSource
        self.preview = preview
        self.view = view
    }
    
    var url: URL
    var dataSource: (_ sourceUrl: URL) async -> Data?
    @ViewBuilder var preview: () -> PreviewView?
    var view: (
        _ data: Data,
        _ updateHandler: any UpdateHandler<Data>
    ) -> ContentsView
    
    private enum DataState {
        case loaded(Data)
        case failed
    }
    @State private var dataState: DataState?
    
    var body: some View {
        Group {
            if let dataState {
                switch dataState {
                case .loaded(let data):
                    view(data, self)
                case .failed:
                    ScrollView {
                        LoadingFailedView(url: url)
                    }
                }
            } else {
                if let preview = preview() {
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
            if dataState == nil {
                await update()
            }
        }
        .refreshable {
            await update()
        }
        .onChange(of: url) {
            Task {
                await update()
            }
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
        let data = await dataSource(url)
        update(with: data)
    }

    func update(with data: Data?) {
        if let data {
            self.dataState = .loaded(data)
        } else {
            self.dataState = .failed
        }
    }
}

typealias RemoteView<Data: Sendable, ContentsView: View> = PreviewableRemoteView<Data, ContentsView, EmptyView>
