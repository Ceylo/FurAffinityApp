//
//  PullableFullScreenCoverView.swift
//  FurAffinity
//
//  Created by Ceylo on 28/10/2024.
//

import SwiftUI
import Combine

// TODO: Use navigationTransition() once iOS 17 support is dropped
private struct FadingSheetView<Contents: View>: View {
    @ViewBuilder var contentsBuilder: () -> Contents
    @State private var visible = false
    
    var body: some View {
        Group {
            if visible {
                contentsBuilder()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.background)
                    .transition(.opacity.animation(.easeInOut))
            }
        }
        .presentationBackground(.clear)
        .onAppear {
            visible = true
        }
        .onDisappear {
            visible = false
        }
    }
}

private struct FadingSheetViewModifier<ContentView: View>: ViewModifier {
    @Binding var isPresented: Bool
    var contentViewBuilder: () -> ContentView
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented) {
                FadingSheetView {
                    contentViewBuilder()
                }
            }
            .transaction { transaction in
                transaction.disablesAnimations = true
            }
    }
}

extension View {
    func fadingSheet(
        isPresented: Binding<Bool>,
        @ViewBuilder _ content: @escaping () -> some View
    ) -> some View {
        modifier(FadingSheetViewModifier(
            isPresented: isPresented,
            contentViewBuilder: content
        ))
    }
}

#Preview {
    @Previewable
    @State var isPresented = true
    
    Button("Present!") {
        isPresented.toggle()
    }
    .fadingSheet(isPresented: $isPresented) {
        Rectangle()
            .fill(Color.red)
            .frame(width: 400, height: 500)
    }
}

#Preview {
    @Previewable
    @State var isPresented = true
    
    Button("Present!") {
        isPresented.toggle()
    }
    .fadingSheet(isPresented: $isPresented) {
        Zoomable {
            Image(.appIcon)
                .fixedSize()
                .ignoresSafeArea()
        }
        .secondaryZoomLevel(.fill)
        .zoomRange(0.1...100)
        .ignoresSafeArea()
    }
}
