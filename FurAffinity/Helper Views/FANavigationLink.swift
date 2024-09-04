//
//  FANavigationLink.swift
//  FurAffinity
//
//  Created by Ceylo on 04/09/2024.
//


import SwiftUI
import Combine

extension EnvironmentValues {
    @Entry var navigationStream: PassthroughSubject<FAURL, Never> = .init()
}

struct FANavigationLink<ContentView: View>: View {
    var destination: FAURL?
    var contentView: ContentView
    
    @Environment(\.navigationStream) private var navigationStream
    
    var body: some View {
        if let destination {
            Button {
                navigationStream.send(destination)
            } label: {
                contentView
            }
            // 🫠 https://forums.developer.apple.com/forums/thread/747558
            .buttonStyle(BorderlessButtonStyle())
        } else {
            contentView
        }
    }
    
    init(destination: FAURL?, @ViewBuilder contentViewBuilder: () -> ContentView) {
        self.destination = destination
        self.contentView = contentViewBuilder()
    }
}
