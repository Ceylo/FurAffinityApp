//
//  Zoomable.swift
//  FurAffinityUI (Android)
//
//  Android counterpart of the iOS `Zoomable`, which is a `UIViewControllerRepresentable`
//  around a `UIScrollView`. Same name and the same chaining API
//  (`initialZoomLevel`/`primaryZoomLevel`/`secondaryZoomLevel` over `ZoomLevel`), built
//  on `MagnifyGesture` + `DragGesture` + a tap gesture instead.
//
//  The content's natural size can't be read back the way `intrinsicContentSize` gives it
//  on iOS, so the caller states it via `contentSize(_:)` — `SubmissionMainImage` knows it
//  from the submission's aspect ratio. Without it, zoom levels fall back to `fit`.
//
//  Pull-to-dismiss is *not* this view's: it is Compose's, from the `ModalBottomSheet`
//  behind `fadingSheet`. All this view contributes is `interactiveDismissDisabled`,
//  saying whether a vertical drag still has somewhere to pan — the declared equivalent of
//  the negotiation iOS gets free between `UIScrollView` and
//  `UISheetPresentationController`.
//
//  Rebuilding it on a `ScrollView([.horizontal, .vertical])` was rejected: Compose has no
//  zoomable scroll container (`transformable`/`detectTransformGestures` hand you deltas to
//  apply yourself), and SkipUI drives both axes of a two-axis `ScrollView` off a single
//  `rememberScrollState`, so it can't pan X and Y independently.
//

import SwiftUI

/// How far a drag must travel before it counts as a pan rather than a tap.
private let panSlop: Double = 4

public enum ZoomLevel {
    case fit
    case fill
    /// minimum between `fill` and `scaledFit(scale: maxScaledFit)`.
    case boundedFill(maxScaledFit: Float)
    /// `scale` x `fit`.
    case scaledFit(scale: Float)
}

public struct Zoomable<Content: View>: View {
    private let content: Content
    private var initialZoomLevel: ZoomLevel = .fit
    private var primaryZoomLevel: ZoomLevel = .fit
    private var secondaryZoomLevel: ZoomLevel = .scaledFit(scale: 2)
    /// Width over height of the content, used to derive fit/fill scales.
    private var contentAspectRatio: Double = 1

    // Not private: skipstone can't bridge a private @State/@Environment.
    @State var scale: Double = 1
    @State var offset = CGSize.zero
    /// Committed values, so a gesture composes with what came before it.
    @State var baseScale: Double = 1
    @State var baseOffset = CGSize.zero
    /// Set by the first zoom or pan of a presentation. Until then the initial zoom is
    /// re-derived from every new viewport measurement — the sheet reports a shorter one
    /// before its insets settle, and latching on that first value left the content
    /// visibly short of `boundedFill`.
    @State var hasUserAdjusted = false
    /// Latched once a drag passes the slop, so a pan's release can't be taken for a tap.
    @State var didPan = false
    /// Latched when the current drag is the sheet's pull. The content then stays put for
    /// the rest of the gesture — including on the horizontal axis, which would otherwise
    /// drift sideways while the sheet travels down.
    @State var sheetOwnsDrag = false
    /// Bumped by `toggleZoom`, so `.animation(_:value:)` animates that one target and
    /// nothing else. `withAnimation` marks the whole Compose frame, which arms the
    /// `Animatable`s behind `scaleEffect`/`offset`; an armed one restarts on every
    /// per-frame gesture write and eases towards a target the finger keeps moving.
    @State var zoomToggleCount = 0
    /// Last measured viewport. Restored with the rest of the state, so a re-presentation
    /// can reset the zoom before Compose has measured again.
    @State var viewport = Foundation.CGSize.zero

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public func initialZoomLevel(_ zoomLevel: ZoomLevel) -> Self {
        var copy = self
        copy.initialZoomLevel = zoomLevel
        return copy
    }

    public func primaryZoomLevel(_ zoomLevel: ZoomLevel) -> Self {
        var copy = self
        copy.primaryZoomLevel = zoomLevel
        return copy
    }

    public func secondaryZoomLevel(_ zoomLevel: ZoomLevel) -> Self {
        var copy = self
        copy.secondaryZoomLevel = zoomLevel
        return copy
    }

    /// Width over height of the zoomed content. iOS reads this from the hosted view's
    /// `intrinsicContentSize`; here the caller supplies it.
    public func contentAspectRatio(_ ratio: Double) -> Self {
        var copy = self
        copy.contentAspectRatio = ratio
        return copy
    }

    public var body: some View {
        GeometryReader { geometry in
            // Whoever has somewhere to go owns vertical drags: the content while it can
            // still be panned, the sheet once it can't. SkipUI passes this preference
            // straight to `ModalBottomSheet`'s `sheetGesturesEnabled`, so it tracks the
            // zoom live, one composition behind.
            let canPanVertically = maxOffset(in: viewport).height > 0.5

            content
                .aspectRatio(contentAspectRatio, contentMode: .fit)
                .scaleEffect(scale)
                .offset(x: offset.width, y: offset.height)
                .animation(.default, value: zoomToggleCount)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
                            hasUserAdjusted = true
                            scale = clamped(baseScale * value.magnification, in: viewport)
                        }
                        .onEnded { _ in
                            baseScale = scale
                            offset = clampedOffset(offset, in: viewport)
                            baseOffset = offset
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            let translation = value.translation
                            // Measured from the gesture's own start, so still being
                            // within the slop means a new gesture: reset there.
                            guard abs(translation.width) > panSlop
                                    || abs(translation.height) > panSlop else {
                                didPan = false
                                sheetOwnsDrag = false
                                return
                            }

                            // The first change with a direction picks the owner for the
                            // whole gesture: a pan can't become a pull halfway.
                            if !didPan {
                                didPan = true
                                sheetOwnsDrag = abs(translation.height) > abs(translation.width)
                                    && maxOffset(in: viewport).height <= 0.5
                            }

                            // Compose is already translating the sheet; moving the
                            // content too would double it.
                            guard !sheetOwnsDrag else { return }

                            hasUserAdjusted = true
                            offset = clampedOffset(
                                CGSize(
                                    width: baseOffset.width + translation.width,
                                    height: baseOffset.height + translation.height
                                ),
                                in: viewport
                            )
                        }
                        .onEnded { _ in
                            // SkipUI routes the simultaneous detector's `onDragCancel`
                            // here, so a plain tap ends up in `onEnded` too, with no
                            // `onChanged` before it. `didPan` is left for the tap that
                            // follows a pan to clear.
                            guard didPan else { return }
                            sheetOwnsDrag = false
                            baseOffset = offset
                        }
                )
                // SkipUI's simultaneous-drag detector never *consumes* pointer events,
                // so Compose's tap detector survives a pan and fires on its release too.
                // Clearing the latch here is what makes a pan swallow one tap, not all.
                .onTapGesture {
                    guard !didPan else {
                        didPan = false
                        return
                    }
                    toggleZoom(in: viewport)
                }
                .interactiveDismissDisabled(canPanVertically)
                // Keyed on the viewport, not `onAppear` alone: the first composition can
                // run before Compose has measured it, and every zoom level derives from
                // that size — applying at 0×0 would silently latch the viewer at fit.
                // Every *later* measurement re-derives it too, until the user zooms or
                // pans: the sheet's first measurement is short of its final height, and
                // the initial zoom computed from it leaves the content letterboxed.
                .onChange(of: Foundation.CGSize(geometry.size), initial: true) { _, size in
                    guard size.width > 0, size.height > 0 else { return }
                    viewport = size
                    guard !hasUserAdjusted else { return }
                    resetForPresentation(in: size)
                }
                // `onAppear` is backed by a plain `remember`, so unlike the state it does
                // re-run per presentation — and it runs before the fresh measurement.
                // The restored viewport is only an approximation (the sheet is remeasured
                // 24pt shorter as it dismisses), so reset from it to avoid a flash and
                // let the measurement above re-apply the real initial zoom.
                .onAppear {
                    resetForPresentation(in: viewport)
                }
        }
    }

    /// Puts the viewer back to its opening state. Needed because skipstone backs `@State`
    /// with `rememberSaveable`, which restores the previous presentation's zoom and pan.
    private func resetForPresentation(in viewport: Foundation.CGSize) {
        offset = .zero
        baseOffset = .zero
        didPan = false
        sheetOwnsDrag = false
        hasUserAdjusted = false
        scale = viewport.width > 0 && viewport.height > 0
            ? self.scale(for: initialZoomLevel, in: viewport)
            : 1
        baseScale = scale
        // `zoomToggleCount` is deliberately not reset: bumping it back to 0 is itself a
        // change, and would animate the snap to the initial zoom. It and the value
        // `.animation` remembers are both `rememberSaveable`, so they stay in step
        // across a presentation on their own.
    }

    // MARK: - Zoom levels

    /// `content` is laid out `.fit` already, so "fit" is scale 1 and "fill" is however
    /// much more is needed to cover the viewport's other axis.
    private func fillScale(in viewport: Foundation.CGSize) -> Double {
        guard viewport.width > 0, viewport.height > 0 else { return 1 }
        let viewportRatio = viewport.width / viewport.height
        return contentAspectRatio > viewportRatio
            ? contentAspectRatio / viewportRatio
            : viewportRatio / contentAspectRatio
    }

    private func scale(for zoomLevel: ZoomLevel, in viewport: Foundation.CGSize) -> Double {
        switch zoomLevel {
        case .fit:
            1
        case .fill:
            fillScale(in: viewport)
        case let .boundedFill(maxScaledFit):
            min(Double(maxScaledFit), fillScale(in: viewport))
        case let .scaledFit(scale):
            Double(scale)
        }
    }

    private func toggleZoom(in viewport: Foundation.CGSize) {
        let primary = scale(for: primaryZoomLevel, in: viewport)
        let target = abs(scale - primary) < 1e-3
            ? scale(for: secondaryZoomLevel, in: viewport)
            : primary
        hasUserAdjusted = true
        scale = max(1, target)
        baseScale = scale
        offset = clampedOffset(.zero, in: viewport)
        baseOffset = offset
        // Arms `.animation(_:value:)` for this one composition — the "target set once"
        // shape, the only one that survives a gesture running alongside it.
        zoomToggleCount += 1
    }

    // MARK: - Bounds

    private func clamped(_ scale: Double, in viewport: Foundation.CGSize) -> Double {
        min(max(scale, 1), 10)
    }

    /// How far the scaled content can be panned from centre before an edge would show.
    private func maxOffset(in viewport: Foundation.CGSize) -> CGSize {
        guard viewport.width > 0, viewport.height > 0 else { return .zero }

        // The content is `.fit` inside the viewport before scaling, so one axis matches
        // the viewport and the other is shorter.
        let viewportRatio = viewport.width / viewport.height
        let fittedWidth = contentAspectRatio > viewportRatio ? viewport.width : viewport.height * contentAspectRatio
        let fittedHeight = contentAspectRatio > viewportRatio ? viewport.width / contentAspectRatio : viewport.height

        return CGSize(
            width: max((fittedWidth * scale - viewport.width) / 2, 0),
            height: max((fittedHeight * scale - viewport.height) / 2, 0)
        )
    }

    /// Keeps the panned content covering the viewport instead of drifting off-screen.
    private func clampedOffset(_ offset: CGSize, in viewport: Foundation.CGSize) -> CGSize {
        // A degenerate viewport yields zero bounds, which clamps to `.zero` anyway.
        let bounds = maxOffset(in: viewport)
        return CGSize(
            width: min(max(offset.width, -bounds.width), bounds.width),
            height: min(max(offset.height, -bounds.height), bounds.height)
        )
    }
}
