//
//  Zoomable.swift
//
//
//  Created by Ceylo on 11/12/2021.
//

import UIKit
import SwiftUI

public enum ZoomLevel {
    case fit
    case fill
    /// minimum between `fill` and `scaledFit(scale: maxScaledFit)`.
    case boundedFill(maxScaledFit: Float)
    /// `scale` x `fit`.
    case scaledFit(scale: Float)
}

public struct Zoomable<Content: View>: UIViewControllerRepresentable {
    private let host: UIHostingController<Content>
    private var initialZoomLevel: ZoomLevel = .fit
    private var primaryZoomLevel: ZoomLevel = .fit
    private var secondaryZoomLevel: ZoomLevel = .scaledFit(scale: 2)
    
    public init(@ViewBuilder content: () -> Content) {
        self.host = UIHostingController(rootView: content())
        // Don't inset the hosted image by the safe area: the scroll view fills the
        // screen edge-to-edge, so a safe-area inset here would leave a margin
        // (e.g. under the status bar) when the image is panned to its edge.
        self.host.safeAreaRegions = []
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
    
    public func makeUIViewController(context: Context) -> ZoomableViewController {
        ZoomableViewController(
            view: self.host.view,
            initialZoomLevel: self.initialZoomLevel,
            primaryZoomLevel: self.primaryZoomLevel,
            secondaryZoomLevel: self.secondaryZoomLevel
        )
    }
    
    public func updateUIViewController(_ uiViewController: ZoomableViewController, context: Context) {
        uiViewController.view.layoutIfNeeded()
    }
}

/// Scroll view that declines to start its own pan for a vertical-dominant drag when
/// there is no vertical scroll room, letting the touches fall through to the
/// fullScreenCover's zoom-transition dismiss gesture (pull-to-dismiss). Horizontal
/// drags and any vertically-scrollable state keep scrolling normally.
class DismissFriendlyScrollView: UIScrollView {
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Only gate our own pan; leave pinch/zoom, tap, etc. to the default behavior.
        guard gestureRecognizer == panGestureRecognizer else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }

        // Velocity is reliable at begin time; translation is still ~0.
        let velocity = panGestureRecognizer.velocity(in: self)
        let verticalDominant = abs(velocity.y) > abs(velocity.x)

        let insets = adjustedContentInset
        let range = contentSize.height + insets.top + insets.bottom - bounds.height
        let canScrollVertically = range > 0.5

        if verticalDominant && !canScrollVertically {
            return false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}

public class ZoomableViewController : UIViewController, UIScrollViewDelegate {
    let scrollView = DismissFriendlyScrollView()
    let contentView: UIView
    let originalContentSize: CGSize
    let initialZoomLevel: ZoomLevel
    let primaryZoomLevel: ZoomLevel
    let secondaryZoomLevel: ZoomLevel
    private var didConfigureInitialZoom = false

    init(
        view: UIView,
        initialZoomLevel: ZoomLevel,
        primaryZoomLevel: ZoomLevel,
        secondaryZoomLevel: ZoomLevel
    ) {
        self.scrollView.maximumZoomScale = 10
        self.contentView = view
        self.originalContentSize = view.intrinsicContentSize
        self.initialZoomLevel = initialZoomLevel
        self.primaryZoomLevel = primaryZoomLevel
        self.secondaryZoomLevel = secondaryZoomLevel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        
        let gestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(tap))
        gestureRecognizer.numberOfTapsRequired = 1
        gestureRecognizer.numberOfTouchesRequired = 1
        scrollView.addGestureRecognizer(gestureRecognizer)
        
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)
        self.view.addSubview(scrollView)
        
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
    
    public override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        guard parent != nil else { return }
        guard !didConfigureInitialZoom else { return }
        didConfigureInitialZoom = true

        let fitZoomLevel = zoomToFit(size: originalContentSize)
        scrollView.minimumZoomScale = fitZoomLevel
        
        scrollView.zoomScale = 1.0
        scrollView.contentSize = originalContentSize
        scrollView.zoomScale = fitZoomLevel
        
        // Not animated: the presenting hero zoom transition already animates the
        // thumbnail into this view, so an animated initial zoom here would read as
        // an unexpected second animation once the transition settles.
        Task {
            scrollView.setZoomScale(initialScale, animated: false)
        }
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        centerSmallContents()
    }
    
    func centerSmallContents() {
        let contentSize = contentView.frame.size
        let offsetX = max((scrollView.bounds.width - contentSize.width) * 0.5, 0)
        let offsetY = max((scrollView.bounds.height - contentSize.height) * 0.5, 0)
        scrollView.contentInset = UIEdgeInsets(top: offsetY, left: offsetX, bottom: 0, right: 0)
    }
    
    // MARK: UIScrollViewDelegate
    public func viewForZooming(in scrollView: UIScrollView) -> UIView? { contentView }
    public func scrollViewDidZoom(_ scrollView: UIScrollView) { centerSmallContents() }
    
    // MARK: - Zoom levels
    func zoomToFit(size: CGSize) -> CGFloat {
        let widthRatio = self.scrollView.frame.width / size.width
        let heightRatio = self.scrollView.frame.height / size.height
        return min(widthRatio, heightRatio)
    }
    
    func zoomToFill(size: CGSize) -> CGFloat {
        let widthRatio = self.scrollView.frame.width / size.width
        let heightRatio = self.scrollView.frame.height / size.height
        return max(widthRatio, heightRatio)
    }
    
    private func scale(for zoomLevel: ZoomLevel) -> CGFloat {
        switch zoomLevel {
        case .fit:
            zoomToFit(size: originalContentSize)
        case .fill:
            zoomToFill(size: originalContentSize)
        case let .boundedFill(maxScaledFit):
            min(CGFloat(maxScaledFit) * zoomToFit(size: originalContentSize), zoomToFill(size: originalContentSize))
        case let .scaledFit(scale):
            CGFloat(scale) * zoomToFit(size: originalContentSize)
        }
    }
    
    var initialScale: CGFloat { scale(for: initialZoomLevel) }
    var primaryScale: CGFloat { scale(for: primaryZoomLevel) }
    var secondaryScale: CGFloat { scale(for: secondaryZoomLevel) }
    
    @objc func tap(sender: Any) {
        let currentScale = scrollView.zoomScale
        let inPrimaryScale = abs(currentScale - primaryScale) < 1e-3
        
        let newScale = max(scrollView.minimumZoomScale, inPrimaryScale ? secondaryScale : primaryScale)
        if currentScale != newScale {
            scrollView.setZoomScale(newScale, animated: true)
        }
    }
}

extension CGSize {
    static func * (size: CGSize, scalar: CGFloat) -> CGSize {
        CGSize(width: size.width * scalar, height: size.height * scalar)
    }
}

#Preview {
    Zoomable {
        Image(.appIcon)
            .ignoresSafeArea()
    }
    .secondaryZoomLevel(.fill)
    .ignoresSafeArea()
}
