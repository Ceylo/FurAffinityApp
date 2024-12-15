//
//  Zoomable.swift
//
//
//  Created by Ceylo on 11/12/2021.
//

import UIKit
import SwiftUI

public enum ZoomLevel {
    case fill
    case scale(value: Float)
}

public struct Zoomable<Content: View>: UIViewControllerRepresentable {
    private let host: UIHostingController<Content>
    private var zoomRange: ClosedRange<CGFloat> = 0.1...10
    private var tapZoomLevel: ZoomLevel = .scale(value: 2)
    
    public init(@ViewBuilder content: () -> Content) {
        self.host = UIHostingController(rootView: content())
    }
    
    public func zoomRange(_ range: ClosedRange<CGFloat>) -> Self {
        var copy = self
        copy.zoomRange = range
        return copy
    }
    
    public func tapZoomLevel(_ zoomLevel: ZoomLevel) -> Self {
        var copy = self
        copy.tapZoomLevel = zoomLevel
        return copy
    }
    
    public func makeUIViewController(context: Context) -> ZoomableViewController {
        ZoomableViewController(
            view: self.host.view,
            zoomRange: self.zoomRange,
            tapZoomLevel: self.tapZoomLevel
        )
    }
    
    public func updateUIViewController(_ uiViewController: ZoomableViewController, context: Context) {
        uiViewController.view.layoutIfNeeded()
    }
}

public class ZoomableViewController : UIViewController, UIScrollViewDelegate {
    let scrollView = UIScrollView()
    let contentView: UIView
    let originalContentSize: CGSize
    let tapZoomLevel: ZoomLevel
    
    init(
        view: UIView,
        zoomRange: ClosedRange<CGFloat>,
        tapZoomLevel: ZoomLevel
    ) {
        self.scrollView.minimumZoomScale = zoomRange.lowerBound
        self.scrollView.maximumZoomScale = zoomRange.upperBound
        self.contentView = view
        self.originalContentSize = view.intrinsicContentSize
        self.tapZoomLevel = tapZoomLevel
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

        let fitZoomLevel = zoomToFit(size: originalContentSize)
        scrollView.minimumZoomScale = fitZoomLevel
        
        scrollView.zoomScale = 1.0
        scrollView.contentSize = originalContentSize
        scrollView.zoomScale = fitZoomLevel
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
    
    // MARK: - ZoomToFit
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
    
    @objc func tap(sender: Any) {
        let fitScale = zoomToFit(size: originalContentSize)
        let zoomedScale = switch tapZoomLevel {
        case .fill:
            zoomToFill(size: originalContentSize)
        case .scale(let value):
            CGFloat(value) * fitScale
        }
        let currentScale = scrollView.zoomScale
        let alreadyInFit = abs(currentScale - fitScale) < 1e-3
        
        let newScale = max(scrollView.minimumZoomScale, alreadyInFit ? zoomedScale : fitScale)
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
    .zoomRange(1...20)
    .tapZoomLevel(.fill)
    .ignoresSafeArea()
}
