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
//  It also owns the viewer's pull-to-dismiss, because only it knows whether a downward
//  drag has anywhere left to pan; iOS gets that free from `UISheetPresentationController`.
//
//  Rebuilding it on a `ScrollView([.horizontal, .vertical])` was rejected: SwiftUI has no
//  zoomable scroll view (magnification is a `UIScrollView` feature), so the pinch, the
//  content sizing and the initial zoom would still be hand-rolled, against
//  `ScrollViewReader`'s JNI local-ref hazard, to buy only `ModalBottomSheet`'s
//  nested-scroll dismissal.
//

import SwiftUI

/// How far a drag must travel before it counts as a pan rather than a tap.
private let panSlop: Double = 4

/// How far the content must be pulled down before releasing dismisses the viewer.
private let dismissThreshold: Double = 120

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
    @State var didApplyInitialZoom = false
    /// Latched once a drag passes the slop, so a pan's release can't be taken for a tap.
    @State var didPan = false
    /// Set when the current drag is pulling the viewer closed rather than panning.
    @State var isDismissDrag = false
    @State var dismissOffset = CGSize.zero
    /// Last measured viewport. Restored with the rest of the state, so a re-presentation
    /// can reset the zoom before Compose has measured again.
    @State var viewport = Foundation.CGSize.zero

    @Environment(\.dismiss) var dismiss

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
            // iOS's sheet dims the page behind as the pull travels. Fading `fadingSheet`'s
            // backdrop can't do that here: SkipUI hands `ModalBottomSheet` a
            // `Color.Unspecified` container that paints an opaque grey, so what the fade
            // reveals is that grey, not the page. Fade and shrink the content instead.
            let dismissProgress = min(max(dismissOffset.height, 0) / dismissThreshold, 1)

            content
                .aspectRatio(contentAspectRatio, contentMode: .fit)
                .scaleEffect(scale * (1 - 0.08 * dismissProgress))
                .offset(
                    x: offset.width + dismissOffset.width,
                    y: offset.height + dismissOffset.height
                )
                .opacity(1 - 0.4 * dismissProgress)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in
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
                                isDismissDrag = false
                                dismissOffset = .zero
                                return
                            }

                            // The first change with a direction picks the mode for the
                            // whole gesture: a pan can't become a dismiss halfway.
                            if !didPan {
                                didPan = true
                                isDismissDrag = isDismissPull(translation, in: viewport)
                            }

                            if isDismissDrag {
                                dismissOffset = translation
                            } else {
                                offset = CGSize(
                                    width: baseOffset.width + translation.width,
                                    height: baseOffset.height + translation.height
                                )
                            }
                        }
                        .onEnded { _ in
                            // SkipUI routes the simultaneous detector's `onDragCancel`
                            // here, so a plain tap ends up in `onEnded` too, with no
                            // `onChanged` before it. `didPan` is left for the tap that
                            // follows a pan to clear.
                            guard didPan else { return }

                            guard isDismissDrag else {
                                offset = clampedOffset(offset, in: viewport)
                                baseOffset = offset
                                return
                            }

                            let shouldDismiss = dismissOffset.height > dismissThreshold
                            isDismissDrag = false
                            if shouldDismiss {
                                dismissOffset = .zero
                                dismiss()
                            } else {
                                // The one target that is set once and stays, so the only
                                // one that can be animated without stalling the pull.
                                withAnimation { dismissOffset = .zero }
                            }
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
                // Keyed on the viewport, not `onAppear` alone: the first composition can
                // run before Compose has measured it, and every zoom level derives from
                // that size — applying at 0×0 would silently latch the viewer at fit.
                .onChange(of: Foundation.CGSize(geometry.size), initial: true) { _, size in
                    guard size.width > 0, size.height > 0 else { return }
                    viewport = size
                    guard !didApplyInitialZoom else { return }
                    didApplyInitialZoom = true
                    resetForPresentation(in: size)
                }
                // `onAppear` is backed by a plain `remember`, so unlike the state it does
                // re-run per presentation — and it runs before the fresh measurement.
                // The restored viewport is only an approximation (the sheet is remeasured
                // 24pt shorter as it dismisses), so reset from it to avoid a flash and
                // let the measurement above re-apply the real initial zoom.
                .onAppear {
                    didApplyInitialZoom = false
                    resetForPresentation(in: viewport)
                }
        }
    }

    /// Puts the viewer back to its opening state. Needed because skipstone backs `@State`
    /// with `rememberSaveable`, which restores the previous presentation's pull and zoom.
    private func resetForPresentation(in viewport: Foundation.CGSize) {
        offset = .zero
        baseOffset = .zero
        dismissOffset = .zero
        didPan = false
        isDismissDrag = false
        scale = viewport.width > 0 && viewport.height > 0
            ? self.scale(for: initialZoomLevel, in: viewport)
            : 1
        baseScale = scale
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
        // `withAnimation` marks the whole Compose frame on SkipUI, so it is banned in
        // shared code — tolerable here only because the viewer is full-screen.
        withAnimation {
            scale = max(1, target)
            baseScale = scale
            offset = clampedOffset(.zero, in: viewport)
            baseOffset = offset
        }
    }

    // MARK: - Dismissal

    /// A downward drag dismisses only when panning has nothing left to give: dominantly
    /// vertical, and already at the bottom-most pan position — which includes `maxY == 0`,
    /// an image small enough to be wholly visible.
    private func isDismissPull(_ translation: CGSize, in viewport: Foundation.CGSize) -> Bool {
        guard translation.height > 0, translation.height > abs(translation.width) else {
            return false
        }
        return baseOffset.height >= maxOffset(in: viewport).height - 0.5
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
