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
    func update(with data: Data)
}

/// `PreviewableRemoteView` provides common behavior for remotely loaded content, such as:
/// - displaying a progress until content becomes available
/// - displaying a incomplete view until the content is loaded
/// - allowing pull to refresh
/// - giving web access to the content
///
/// - Note: By using `PreviewableRemoteView` instead of `RemoteView`, you take over the
/// responsibility of providing a primary toolbar item on `ContentsView`.
/// For consistency, it is recommended to reuse `RemoteContentToolbarItem`, eventually
/// giving it your own custom additional items.
/// A default primary toolbar item is already provided for all other states
/// (preview, loading, failure).
struct PreviewableRemoteView<Data: Sendable, ContentsView: View, PreviewView: View>: View, UpdateHandler {
    init(
        url: URL,
        preloadedData: Data? = nil,
        dataSource: @escaping (_ sourceUrl: URL) async throws -> Data,
        @ViewBuilder preview: @escaping () -> PreviewView? = { nil },
        view: @escaping (Data, any UpdateHandler<Data>) -> ContentsView
    ) {
        self.url = url
        self.preloadedData = preloadedData
        self.dataSource = dataSource
        self.preview = preview
        self.view = view
    }
    
    var url: URL
    var preloadedData: Data?
    var dataSource: (_ sourceUrl: URL) async throws -> Data
    @ViewBuilder var preview: () -> PreviewView?
    var view: (
        _ data: Data,
        _ updateHandler: any UpdateHandler<Data>
    ) -> ContentsView
    
    private enum DataState {
        case loaded(Data)
        case updating(oldData: Data)
        case failed(error: LocalizedError)
    }
    @State private var dataState: DataState?
    @State private var showUpdateLoadingView = false
    @State private var activity: NSUserActivity?
    
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
                case let .failed(error):
                    ScrollView {
                        LoadingFailedView(url: url, error: error)
                            .toolbar { RemoteContentToolbarItem(url: url) }
                    }
                }
            } else {
                Group {
                    if let preview = preview() {
                        preview
                    } else {
                        loadingView
                    }
                }
                .toolbar { RemoteContentToolbarItem(url: url) }
            }
        }
        .task {
            if dataState == nil {
                if let preloadedData {
                    update(with: preloadedData)
                } else {
                    await update()
                }
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
            
            if let activity {
                activity.resignCurrent()
                let newActivity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
                newActivity.webpageURL = url
                self.activity = newActivity
            }
        }
        .onAppear {
            if activity == nil {
                let activity = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
                activity.webpageURL = url
                self.activity = activity
            }
        }
        .onDisappear {
            activity = nil
        }
        .onChange(of: activity) { oldValue, newValue in
            oldValue?.resignCurrent()
            newValue?.becomeCurrent()
        }
    }
    
    func update() async {
        do {
            let data = try await dataSource(url)
            update(with: data)
        } catch {
            self.dataState = .failed(error: LocalizedErrorWrapper(error))
        }
    }

    func update(with data: Data) {
        self.dataState = .loaded(data)
    }
}

@MainActor
func RemoteView<Data: Sendable, ContentsView: View>(
    url: URL,
    preloadedData: Data? = nil,
    dataSource: @escaping (_ sourceUrl: URL) async throws -> Data,
    view: @escaping (Data, any UpdateHandler<Data>) -> ContentsView
) -> some View {
    PreviewableRemoteView<_, _, EmptyView>(
        url: url,
        preloadedData: preloadedData,
        dataSource: dataSource,
        view: { data, updateHandler in
            view(data, updateHandler)
                .toolbar { RemoteContentToolbarItem(url: url) }
        }
    )
}

#Preview {
    @Previewable
    @State var url = URL(string: "https://www.furaffinity.net/")!
    
    NavigationStack {
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
}
