//
//  View+fadingSheet.swift
//  FurAffinityUI (Android)
//
//  Android counterpart of `fadingSheet` from the iOS `View+pullableScreenCover`, which
//  crossfades a UIKit-backed `.sheet` so the viewer inherits
//  `UISheetPresentationController`'s pull-to-dismiss.
//
//  SkipUI implements `sheet` and `fullScreenCover` as the same Compose
//  `ModalBottomSheet` — `isFullScreen: true` only drops the corner radius and the drag
//  handle — so there is nothing to crossfade *between*, and the pull-to-dismiss is
//  `Zoomable`'s, over the `\.dismiss` action this presentation publishes.
//
//  Unguarded because the Darwin bridge compile has `os(Android) == false` and would
//  otherwise see no declaration at all.
//

import SwiftUI

extension View {
    func fadingSheet(
        isPresented: Binding<Bool>,
        @ViewBuilder _ content: @escaping () -> some View
    ) -> some View {
        fullScreenCover(isPresented: isPresented) {
            ZStack {
                // The presentation has none of its own, so the page behind would show
                // through wherever the content doesn't cover.
                Color.black
                    .ignoresSafeArea()

                content()
            }
        }
    }
}
