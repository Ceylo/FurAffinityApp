//
//  ProgressiveLoadItem.swift
//  FurAffinity
//
//  Created by Ceylo on 04/09/2024.
//

import SwiftUI
import FAKit

protocol ProgressiveData: Equatable {
    var canLoadMore: Bool { get }
}

struct ProgressiveLoadItem<DataType: ProgressiveData>: View {
    var label: String
    var currentData: DataType
    var loadMoreData: (_ currentData: DataType) -> Void
    var crawlingDelay: Duration = .seconds(1.0)
    @State private var needsMoreData = false
    
    var body: some View {
        Group {
            if currentData.canLoadMore {
                HStack {
                    ProgressView()
                    Text(label)
                }
                .onAppear {
                    needsMoreData = true
                    loadMoreData(currentData)
                }
                .onDisappear {
                    needsMoreData = false
                }
            }
        }
        .onChange(of: currentData) { _, newData in
            if needsMoreData && newData.canLoadMore {
                Task {
                    guard needsMoreData else { return }
                    try await Task.sleep(for: crawlingDelay)
                    guard needsMoreData else { return }
                    loadMoreData(newData)
                }
            }
        }
    }
}

extension [Int]: ProgressiveData {
    var canLoadMore: Bool { true }
}

#Preview {
    @Previewable @State var data = [42]
    List {
        ForEach(data, id: \.self) { item in
            Text("\(item)")
        }
        
        ProgressiveLoadItem(
            label: "Loading more numbers…",
            currentData: data,
            loadMoreData: { latestData in
                let oldData = latestData.count < 10 ? latestData : []
                data = oldData + [latestData.last! + 1]
            }
        )
    }
    .listStyle(.plain)
}
