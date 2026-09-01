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

// Android's `OverScroller.SplineOverScroller` constants, in dp — a dp is 1/160 inch by
// definition, so the density term of Android's own coefficient is exactly 160.
private let flingFriction = 0.015                              // ViewConfiguration.SCROLL_FRICTION
private let flingPhysicalCoeff = 9.80665 * 39.37 * 160 * 0.84  // g x in/m x dp/in x tuning
private let flingInflexion = 0.35
private let flingDecelerationRate = Foundation.log(0.78) / Foundation.log(0.9)
/// Below this a release is a stop, not a flick.
private let minimumFlingSpeed: Double = 50                     // dp/s
/// Compose's `VelocityTracker` staleness window: samples further apart than this start
/// afresh, which is what makes "pan, hold still, lift" not fling.
private let velocitySampleWindow: Foundation.TimeInterval = 0.1
/// Oversamples every panel up to 240 Hz, so no two frames can read the same position.
/// Nothing in SkipSwiftUI aligns work to vsync, so this stands in for a frame clock.
private let motionTick: Duration = .milliseconds(4)
/// Fraction of the finger's travel that still gets through just past a bound.
private let overscrollRubber = 0.55
/// Compose's `spring(dampingRatio: .noBouncy, stiffness:)` in its own units, so this sits
/// between `StiffnessLow` (200) and `StiffnessMedium` (1500). Settles in ~0.35 s.
private let settleStiffness: Double = 400
/// Below this, in dp, the settle has arrived.
private let settleEpsilon = 0.5

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
    /// Pan speed in dp/s, timed by hand: SkipUI builds every `DragGesture.Value` with
    /// `velocity: .zero`, so there is nothing to read off the gesture.
    @State var panVelocity = CGSize.zero
    @State var lastSampleTime: Double = 0
    @State var lastSampleTranslation = CGSize.zero
    /// Translation already accumulated when the pan took over, discounted from every
    /// offset below. Zero for a gesture that starts on still content — Compose subtracts
    /// its touch slop before the first callback — but not for one that catches a fling.
    @State var panStartTranslation = CGSize.zero
    /// Bumped to cancel whatever fling or settle is running: the loop stops as soon as it
    /// sees a generation other than its own.
    @State var motionGeneration = 0

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
                            stopMotion()
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
                                catchMotion(at: translation)
                                return
                            }

                            // The first change with a direction picks the owner for the
                            // whole gesture: a pan can't become a pull halfway.
                            if !didPan {
                                didPan = true
                                sheetOwnsDrag = abs(translation.height) > abs(translation.width)
                                    && maxOffset(in: viewport).height <= 0.5
                                // Repeated from the branch above, which Compose's slop
                                // subtraction normally runs first but which a coarse
                                // event clearing the slop in one step skips.
                                catchMotion(at: translation)
                            }

                            // Compose is already translating the sheet; moving the
                            // content too would double it.
                            guard !sheetOwnsDrag else { return }

                            sampleVelocity(translation, at: value.time)
                            hasUserAdjusted = true
                            offset = overscrolled(
                                CGSize(
                                    width: baseOffset.width + translation.width - panStartTranslation.width,
                                    height: baseOffset.height + translation.height - panStartTranslation.height
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
                            // Past a bound the pull has to come back before anything
                            // else; within them the release is a fling or nothing.
                            if isOverscrolled(in: viewport) {
                                startSettle(in: viewport)
                            } else {
                                startFling(in: viewport)
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
        stopMotion()
        resetVelocitySampling()
        offset = .zero
        baseOffset = .zero
        panStartTranslation = .zero
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
        stopMotion()
        hasUserAdjusted = true
        scale = max(1, target)
        baseScale = scale
        offset = clampedOffset(.zero, in: viewport)
        baseOffset = offset
        // Arms `.animation(_:value:)` for this one composition — the "target set once"
        // shape, the only one that survives a gesture running alongside it.
        zoomToggleCount += 1
    }

    // MARK: - Inertia

    /// `.animation(_:value:)` cannot drive a value the gesture also writes — an armed
    /// `Animatable` restarts on every per-frame write, and it leaves `offset` already at
    /// its target, so a fling could never be caught mid-flight. The motion is stepped by
    /// hand instead, one `@State` write per tick, exactly as the drag does.
    ///
    /// `step` receives the elapsed time and returns whether to keep going. It must be a
    /// closed form of that time rather than an accumulation, so an overslept tick costs
    /// one frame's smoothness and never distorts the curve.
    private func runMotion(_ step: @escaping @MainActor (Foundation.TimeInterval) -> Bool) {
        motionGeneration += 1
        let generation = motionGeneration
        let start = Foundation.Date()
        Task { @MainActor in
            while true {
                do { try await Task.sleep(for: motionTick) } catch { return }
                guard motionGeneration == generation else { return }
                guard step(Foundation.Date().timeIntervalSince(start)) else {
                    baseOffset = offset
                    return
                }
            }
        }
    }

    private func stopMotion() {
        motionGeneration += 1
    }

    /// Takes a gesture over from whatever motion is running: stops it where it is and
    /// rebases the pan there, so a touch landing on a fling continues from the position
    /// it caught rather than jumping back to where the fling began.
    private func catchMotion(at translation: CGSize) {
        stopMotion()
        baseOffset = offset
        resetVelocitySampling()
        panStartTranslation = translation
    }

    /// Times the pan by hand from successive translations. Weighted towards the newest
    /// sample, the way Compose's tracker is, so a flick after a slow drag still flings.
    private func sampleVelocity(_ translation: CGSize, at time: Foundation.Date) {
        let now = time.timeIntervalSinceReferenceDate
        let dt = now - lastSampleTime
        if lastSampleTime > 0, dt > 0, dt < velocitySampleWindow {
            let sample = CGSize(width: (translation.width - lastSampleTranslation.width) / dt,
                                height: (translation.height - lastSampleTranslation.height) / dt)
            panVelocity = CGSize(width: 0.7 * sample.width + 0.3 * panVelocity.width,
                                 height: 0.7 * sample.height + 0.3 * panVelocity.height)
        } else {
            panVelocity = .zero
        }
        lastSampleTime = now
        lastSampleTranslation = translation
    }

    private func resetVelocitySampling() {
        panVelocity = .zero
        lastSampleTime = 0
        lastSampleTranslation = .zero
    }

    /// The sampled velocity, or zero once it is stale. A finger that stops moving stops
    /// producing events, so the sampler is never called again to notice the pause and the
    /// pre-pause velocity would survive to here. Compose's tracker discards stale samples
    /// when queried; so does this.
    private var releaseVelocity: CGSize {
        let age = Foundation.Date().timeIntervalSinceReferenceDate - lastSampleTime
        return age < velocitySampleWindow ? panVelocity : .zero
    }

    /// Coasts on from the release along the pan's own direction, on Android's spline.
    private func startFling(in viewport: Foundation.CGSize) {
        let velocity = releaseVelocity
        let speed = (velocity.width * velocity.width
                     + velocity.height * velocity.height).squareRoot()
        let bounds = maxOffset(in: viewport)
        guard speed >= minimumFlingSpeed, bounds.width > 0.5 || bounds.height > 0.5 else {
            return
        }

        let duration = flingDuration(speed)
        let distance = flingDistance(speed)
        let direction = CGSize(width: velocity.width / speed,
                               height: velocity.height / speed)
        let start = offset

        runMotion { elapsed in
            let t = min(elapsed / duration, 1)
            let travelled = distance * flingProgress(t)
            // Each axis stops at its own bound rather than the whole fling ending there.
            offset = clampedOffset(
                CGSize(width: start.width + direction.width * travelled,
                       height: start.height + direction.height * travelled),
                in: viewport
            )
            return t < 1
        }
    }

    /// Brings a pull that went past a bound back to it. Critically damped, so an inward
    /// residual velocity simply arrives while the outward velocity of a release from an
    /// overscrolled pull carries a little further first — the visible spring-back.
    private func startSettle(in viewport: Foundation.CGSize) {
        let target = clampedOffset(offset, in: viewport)
        let x0 = CGSize(width: offset.width - target.width,
                        height: offset.height - target.height)
        let v0 = releaseVelocity
        let omega = settleStiffness.squareRoot()

        runMotion { elapsed in
            let decay = Foundation.exp(-omega * elapsed)
            let x = CGSize(
                width: (x0.width + (v0.width + omega * x0.width) * elapsed) * decay,
                height: (x0.height + (v0.height + omega * x0.height) * elapsed) * decay
            )
            guard abs(x.width) >= settleEpsilon || abs(x.height) >= settleEpsilon else {
                offset = target
                return false
            }
            offset = CGSize(width: target.width + x.width, height: target.height + x.height)
            return true
        }
    }

    // Android's `SplineOverScroller` closed forms. The position curve stands in for its
    // 100-entry `SPLINE_POSITION` table: it starts at 0, ends at 1, and its initial slope
    // returns the launch speed exactly, because `distance / (flingInflexion * duration)`
    // is that speed.

    private func splineDeceleration(_ speed: Double) -> Double {
        Foundation.log(flingInflexion * speed / (flingFriction * flingPhysicalCoeff))
    }

    private func flingDuration(_ speed: Double) -> Foundation.TimeInterval {
        Foundation.exp(splineDeceleration(speed) / (flingDecelerationRate - 1))
    }

    private func flingDistance(_ speed: Double) -> Double {
        flingFriction * flingPhysicalCoeff
            * Foundation.exp(flingDecelerationRate / (flingDecelerationRate - 1) * splineDeceleration(speed))
    }

    private func flingProgress(_ t: Double) -> Double {
        1 - Foundation.pow(1 - t, 1 / flingInflexion)
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

    private func isOverscrolled(in viewport: Foundation.CGSize) -> Bool {
        let target = clampedOffset(offset, in: viewport)
        return abs(offset.width - target.width) >= settleEpsilon
            || abs(offset.height - target.height) >= settleEpsilon
    }

    /// Lets a drag continue past its bound against resistance, which is what Android's
    /// zoomable image viewers do. Not the Android-12 stretch overscroll: that belongs to
    /// a scroll container's own edge effect, and there is no scroll container here.
    private func overscrolled(_ offset: CGSize, in viewport: Foundation.CGSize) -> CGSize {
        let bounds = maxOffset(in: viewport)
        return CGSize(
            width: resisted(offset.width, bound: bounds.width, extent: viewport.width),
            height: resisted(offset.height, bound: bounds.height, extent: viewport.height)
        )
    }

    /// Pass-through within the bound; past it `overscrollRubber` of the travel gets
    /// through, asymptoting at `extent` so the content can never be pulled clear of the
    /// viewport however far the finger goes.
    private func resisted(_ value: Double, bound: Double, extent: Double) -> Double {
        let excess = abs(value) - bound
        guard excess > 0, extent > 0 else { return value }
        let through = excess * extent * overscrollRubber / (extent + overscrollRubber * excess)
        return value < 0 ? -(bound + through) : bound + through
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
