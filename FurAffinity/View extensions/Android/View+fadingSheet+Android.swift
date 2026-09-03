//
//  View+fadingSheet.swift
//  FurAffinityUI (Android)
//
//  Android counterpart of `fadingSheet` from the iOS `View+pullableScreenCover`, which
//  crossfades a UIKit-backed `.sheet` so the viewer inherits
//  `UISheetPresentationController`'s pull-to-dismiss.
//
//  Here it is a plain `.sheet`, and that is the whole point: SkipUI renders `sheet` and
//  `fullScreenCover` as the same Compose `ModalBottomSheet`, and `fullScreenCover` is
//  precisely what switches Compose's own pull-to-dismiss off, while a `.sheet` at
//  `.fraction(1)` is full-bleed and keeps it. `Zoomable` arbitrates the rest through
//  `interactiveDismissDisabled`. `Android/docs/screens.md` has the `sheetGesturesEnabled`
//  formula behind all three, and the accepted costs of the swap.
//
//  There is nothing left to crossfade between either — `presentationBackground` is
//  unavailable in skip-fuse-ui, so a fade would reveal the sheet's own opaque `Surface`
//  rather than the page behind it.
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
        sheet(isPresented: isPresented) {
            ZStack {
                // The presentation has none of its own, so the page behind would show
                // through wherever the content doesn't cover.
                Color.black
                    .ignoresSafeArea()

                content()
            }
            // SkipUI turns the detent into the sheet's top inset, so a full fraction is
            // what makes this full-bleed rather than a partial-height sheet.
            .presentationDetents([.fraction(1)])
            .presentationDragIndicator(.hidden)
        }
    }
}
