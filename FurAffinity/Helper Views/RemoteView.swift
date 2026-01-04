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
struct PreviewableRemoteView<Data: Sendable & Equatable, ContentsView: View, PreviewView: View>: View, UpdateHandler {
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
    
    private enum DataState: Equatable {
        case notLoadingYet
        case loading
        case loaded(Data)
        case updating(oldData: Data)
        
        var lastKnownData: Data? {
            switch self {
            case let .loaded(data),
                let .updating(oldData: data):
                data
            case .notLoadingYet, .loading:
                nil
            }
        }
    }
    @State private var dataState: DataState = .notLoadingYet
    @State private var showUpdateLoadingView = false
    @State private var activity: NSUserActivity?
    @Environment(ErrorStorage.self) private var errorStorage
    
    var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
            Link("Waiting for \(url.host(percentEncoded: false) ?? "?")…", destination: url)
                .fixedSize()
        }
    }
    
    var loadingViewWithBackground: some View {
        loadingView
            .padding(20)
            .applying {
                if #available(iOS 26, *) {
                    $0.glassEffect(in: RoundedRectangle(cornerRadius: 10))
                } else {
                    $0
                        .background(.thinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
    }
    
    var body: some View {
        Group {
            switch dataState {
            case .notLoadingYet, .loading:
                Group {
                    if let preview = preview() {
                        preview
                    } else {
                        loadingView
                    }
                }
                .toolbar { RemoteContentToolbarItem(url: url) }
            case .loaded(let data):
                view(data, self)
            case .updating(let oldData):
                ZStack {
                    view(oldData, self)
                    
                    if showUpdateLoadingView {
                        loadingViewWithBackground
                    }
                }
                .modifier(DelayedToggle(toggle: $showUpdateLoadingView, delay: .seconds(1)))
            }
        }
        .task {
            // Dismissed alerts cause new tasks to be scheduled.
            // We only want to trigger the code below on first appear
            guard dataState == .notLoadingYet else { return }
            dataState = .loading
            if let preloadedData {
                update(with: preloadedData)
            } else {
                await storeLocalizedError(in: errorStorage, action: "Loading", webBrowserURL: url, shouldPopNavigationStack: true) {
                    try await update()
                }
            }
        }
        .refreshable(actionTitle: "Refresh", webBrowserURL: url) {
            try await update()
        }
        .onChange(of: url) {
            dataState = switch dataState {
            case .loaded(let data):
                    .updating(oldData: data)
            case .updating(let oldData):
                    .updating(oldData: oldData)
            case .notLoadingYet, .loading:
                    .loading
            }
            
            Task {
                await storeLocalizedError(in: errorStorage, action: "Data Update", webBrowserURL: url) {
                    try await update()
                    
                    dataState = switch dataState {
                    case .loaded(let data):
                            .loaded(data)
                    case .updating(let oldData):
                            .loaded(oldData)
                    case .notLoadingYet, .loading:
                            .loading
                    }
                }
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
    
    func update() async throws {
        let data = try await dataSource(url)
        update(with: data)
    }

    func update(with data: Data) {
        self.dataState = .loaded(data)
    }
}

@MainActor
func RemoteView<Data: Sendable & Equatable, ContentsView: View>(
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
    @Previewable @State var url = URL(string: "https://www.furaffinity.net/")!
    @Previewable @State var errorStorage = ErrorStorage()
    
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
        .environment(errorStorage)
    }
}
