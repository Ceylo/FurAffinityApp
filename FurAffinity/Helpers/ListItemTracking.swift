//
//  ListItemTracking.swift
//  ListItemTracking
//
//  Created by Ceylo on 29/05/2022.
//

import SwiftUI

struct ViewFrameKey: PreferenceKey {
    typealias Value = CGRect?
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout Value, nextValue: () -> Value) {
        value = value?.union(nextValue() ?? .null)
    }
}

struct ItemFrameTracking: ViewModifier {
    var listGeometry: GeometryProxy
    var frameUpdated: (CGRect?) -> Void
    
    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { itemGeometry in
                    let itemFrameIgnoringSafeArea = itemGeometry.frame(in: .named("ListFrame.Scroll"))
                    let parentListFrame = listGeometry.frame(in: .global)
                    let parentListOffset = parentListFrame.origin
                    let itemFrame = CGRect(
                        origin: CGPoint(x: itemFrameIgnoringSafeArea.origin.x - parentListOffset.x,
                                        y: itemFrameIgnoringSafeArea.origin.y - parentListOffset.y),
                        size: itemFrameIgnoringSafeArea.size)
                    let visible = parentListFrame.intersects(itemFrameIgnoringSafeArea)
                    
                    Color.clear.preference(key: ViewFrameKey.self,
                                           value: visible ? itemFrame : nil)
                }
            }
            .onPreferenceChange(ViewFrameKey.self) { frame in
                frameUpdated(frame)
            }
    }
}

struct ListFrameTracking: ViewModifier {
    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: "ListFrame.Scroll")
    }
}

public extension View {
    
    /// Add an action to perform when a List item frame changes. To be used along with ``trackListFrame()``.
    ///
    /// It can be used with this pattern:
    ///
    ///     GeometryReader { geometry in
    ///        List(0..<100) { i in
    ///            Text("Item \(i)")
    ///                .onItemFrameChanged(listGeometry: geometry) { (frame: CGRect?) in
    ///                    print("rect of item \(i): \(String(describing: frame)))")
    ///                }
    ///        }
    ///        .trackListFrame()
    ///     }
    ///
    /// - Parameters:
    ///   - listGeometry: A GeometryProxy from a GeometryReader wrapping your List view.
    ///   - frameUpdated: A closure called each time an item position changes due to scrolling in the List.
    ///   If the item goes out of List's frame, the given CGRect is nil
    func onItemFrameChanged(listGeometry: GeometryProxy, _ frameUpdated: @escaping (CGRect?) -> Void) -> some View {
        modifier(ItemFrameTracking(listGeometry: listGeometry, frameUpdated: frameUpdated))
    }
    
    /// Makes a List view ready for use along with ``onItemFrameChanged(listGeometry:_:)``.
    func trackListFrame() -> some View {
        modifier(ListFrameTracking())
    }
}
