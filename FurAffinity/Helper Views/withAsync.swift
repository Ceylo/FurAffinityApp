//
//  withAsync.swift
//  FurAffinity
//
//  Created by Ceylo on 10/09/2024.
//


import SwiftUI

struct withAsync<DataType: Sendable, SomeView: View>: View {
    var provider: () async throws -> DataType
    var contentsBuilder: (DataType) -> SomeView
    
    init(_ provider: @escaping () async throws -> DataType, contentsBuilder: @escaping (DataType) -> SomeView) {
        self.provider = provider
        self.contentsBuilder = contentsBuilder
    }
    
    @State private var data: DataType?
    var body: some View {
        Group {
            if let data {
                contentsBuilder(data)
            } else {
                Rectangle()
                    .fill(.clear)
            }
        }
        .task {
            data = try? await provider()
        }
    }
}
