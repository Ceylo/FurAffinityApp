//
//  RemoteView.swift
//  FurAffinity
//
//  Created by Ceylo on 19/11/2023.
//

import SwiftUI

/// `RemoteView` provides common behavior for remotely loaded content, such as:
/// - displaying a progress until content becomes available
/// - allowing pull to refresh
/// - giving web access to the content
struct RemoteView<Contents, ContentsView: View>: View {
    var url: URL
    var contentsLoader: () async -> Contents?
    var contentsViewBuilder: (_ contents: Contents, _ refreshHandler: @escaping () -> Void) -> ContentsView
    
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
                    contentsViewBuilder(contents, refresh)
                case .failed:
                    ScrollView {
                        LoadingFailedView(url: url)
                    }
                }
            } else {
                VStack(spacing: 20) {
                    ProgressView()
                    Link("Waiting for \(url.host(percentEncoded: false) ?? "?")…", destination: url)
                }
            }
        }
        .task {
            if contentsState == nil {
                refresh()
            }
        }
        .refreshable {
            refresh()
        }
        .toolbar {
            ToolbarItem {
                Link(destination: url) {
                    Image(systemName: "safari")
                }
            }
        }
    }
    
    func refresh() {
        Task {
            if let contents = await contentsLoader() {
                self.contentsState = .loaded(contents)
            } else {
                self.contentsState = .failed
            }
        }
    }
}
