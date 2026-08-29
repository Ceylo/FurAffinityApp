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
//  handle — so there is nothing to crossfade *between* here, and no sheet-owned
//  pull-to-dismiss to inherit either: the content decides when a downward drag has
//  nowhere left to pan (see `Zoomable`), and calls the `\.dismiss` action the
//  presentation publishes into it.
//
//  Unguarded on purpose: an `os(Android)` guard would leave the shared caller with no
//  declaration at all in the module's Darwin bridge compile, where `os(Android)` is
//  false.
//

import SwiftUI

extension View {
    func fadingSheet(
        isPresented: Binding<Bool>,
        @ViewBuilder _ content: @escaping () -> some View
    ) -> some View {
        fullScreenCover(isPresented: isPresented) {
            ZStack {
                // The presentation itself has no background, so without this the page
                // behind it shows through wherever the content doesn't cover.
                Color.black
                    .ignoresSafeArea()

                content()
            }
        }
    }
}
