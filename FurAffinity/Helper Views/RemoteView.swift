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
        dataSource: @escaping (_ sourceUrl: URL) async throws -> Data?,
        @ViewBuilder preview: @escaping () -> PreviewView? = { nil },
        view: @escaping (Data, any UpdateHandler<Data>) -> ContentsView
    ) {
        self.url = url
        self.dataSource = dataSource
        self.preview = preview
        self.view = view
    }
    
    var url: URL
    var dataSource: (_ sourceUrl: URL) async throws -> Data?
    @ViewBuilder var preview: () -> PreviewView?
    var view: (
        _ data: Data,
        _ updateHandler: any UpdateHandler<Data>
    ) -> ContentsView
    
    private enum DataState {
        case loaded(Data)
        case updating(oldData: Data)
        case failed
    }
    @State private var dataState: DataState?
    @State private var showUpdateLoadingView = false
    
    var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
            Link("Waiting for \(url.host(percentEncoded: false) ?? "?")…", destination: url)
                .fixedSize()
        }
    }
    
    var body: some View {
        Group {
            if let dataState {
                switch dataState {
                case .loaded(let data):
                    view(data, self)
                case .updating(let oldData):
                    ZStack {
                        view(oldData, self)
                        
                        if showUpdateLoadingView {
                            loadingView
                                .padding(20)
                                .background(.thinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    .modifier(DelayedToggle(toggle: $showUpdateLoadingView, delay: .seconds(1)))
                case .failed:
                    ScrollView {
                        LoadingFailedView(url: url)
                    }
                }
            } else {
                if let preview = preview() {
                    preview
                } else {
                    loadingView
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
            let newState: DataState? = switch dataState {
            case .loaded(let data):
                    .updating(oldData: data)
            case .updating(let oldData):
                    .updating(oldData: oldData)
            case .failed, nil:
                nil
            }
            
            dataState = newState
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
        let data = try? await dataSource(url)
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

#Preview {
    @Previewable
    @State var url = URL(string: "https://www.furaffinity.net/")!
    
    RemoteView(url: url) { sourceUrl in
        try await Task.sleep(for: .seconds(1))
        return sourceUrl
    } view: { data, updateHandler in
        VStack {
            Text(data.absoluteString)
            Button("Update") {
                url = url.appending(component: "hi")
            }
        }
        .border(.red)
    }
}
