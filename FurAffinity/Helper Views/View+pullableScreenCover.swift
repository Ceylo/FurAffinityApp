//
//  PullableFullScreenCoverView.swift
//  FurAffinity
//
//  Created by Ceylo on 28/10/2024.
//

import SwiftUI
import Combine

// TODO: Use navigationTransition() once iOS 17 support is dropped
private struct PullableFullScreenCoverView<Contents: View>: View {
    @ViewBuilder
    var contentsBuilder: () -> Contents
    
    @Environment(\.dismiss) private var dismiss
    @State private var visible = false
    @State private var opacity = 1.0
    @State private var offset = CGSize.zero
    @GestureState private var dragGestureActive: Bool = false
    private var scale: CGSize {
        let s = 0.66 + 0.33 * opacity
        return CGSize(width: s, height: s)
    }
    
    var body: some View {
        Group {
            if visible {
                VStack {
                    contentsBuilder()
                        .offset(offset)
                        .scaleEffect(scale, anchor: .bottom)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background)
                .transition(.opacity.animation(.easeInOut))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(opacity)
        .ignoresSafeArea()
        .presentationBackground(.clear)
        .onAppear {
            withAnimation {
                visible = true
            }
        }
        .onDisappear {
            visible = false
        }
        .simultaneousGesture(
            // Below 15, this gesture tends to take precedence over scroll views in
            // the contents view
            DragGesture(minimumDistance: 15, coordinateSpace: .global)
                .updating($dragGestureActive) { _, state, _ in
                    state = true
                }
                .onChanged { value in
                    setAnimationState(AnimationState(for: value.translation))
                }
                .onEnded { value in
                    animate(with: AnimationState(for: value.predictedEndTranslation)) {
                        visible = false
                        dismiss()
                    }
                }
        )
        .onChange(of: dragGestureActive) { _, newIsActiveValue in
            if newIsActiveValue != dragGestureActive {
                // There was a conflict with a gesture in the contents view,
                // reset our animation
                resetAnimation()
            }
        }
    }
    
    fileprivate struct AnimationState {
        let opacity: CGFloat
        let downAmount: CGFloat
        var offset: CGSize {
            CGSize(width: 0, height: downAmount)
        }
    }
    
    private func setAnimationState(_ state: AnimationState) {
        self.offset = state.offset
        self.opacity = state.opacity
    }
    
    private func animate(with state: AnimationState, completion: @escaping () -> Void = {}) {
        if state.opacity == 0 {
            withAnimation(.spring(duration: 0.3), {
                setAnimationState(state)
            }, completion: completion)
        } else {
            resetAnimation()
        }
    }
    
    private func resetAnimation() {
        withAnimation {
            setAnimationState(.init(opacity: 1, downAmount: 0))
        }
    }
}

extension PullableFullScreenCoverView.AnimationState {
    init(for translation: CGSize) {
        let downAmount = max(0, translation.height)
        let opacity = 1 - max(0, min(1, downAmount / 200))
        self.init(opacity: opacity, downAmount: downAmount)
    }
}

private struct PullableScreenCoverViewModifier<ContentView: View>: ViewModifier {
    @Binding var isPresented: Bool
    var contentViewBuilder: () -> ContentView
    
    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $isPresented) {
                PullableFullScreenCoverView {
                    contentViewBuilder()
                }
            }
            .transaction { transaction in
                transaction.disablesAnimations = true
            }
    }
}

extension View {
    func pullableScreenCover(
        isPresented: Binding<Bool>,
        @ViewBuilder _ content: @escaping () -> some View
    ) -> some View {
        modifier(PullableScreenCoverViewModifier(
            isPresented: isPresented,
            contentViewBuilder: content
        ))
    }
}

#Preview {
    @Previewable
    @State var isPresented = false
    
    Button("Present!") {
        isPresented.toggle()
    }
    .pullableScreenCover(isPresented: $isPresented) {
        Image(systemName: "globe")
            .resizable()
            .foregroundStyle(.green)
            .aspectRatio(contentMode: .fit)
    }
}
