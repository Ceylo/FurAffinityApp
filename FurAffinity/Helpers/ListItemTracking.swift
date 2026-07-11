//
//  ListItemTracking.swift
//  ListItemTracking
//
//  Created by Ceylo on 29/05/2022.
//

import SwiftUI

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
        // Snapshot the list frame outside the @Sendable transform closure so it
        // doesn't capture the non-Sendable GeometryProxy. The enclosing
        // GeometryReader re-applies this modifier when the list frame changes.
        let parentListFrame = listGeometry.frame(in: .global)
        return onGeometryChange(for: CGRect?.self) { itemGeometry in
            let itemFrameIgnoringSafeArea = itemGeometry.frame(in: .named("ListFrame.Scroll"))
            let parentListOffset = parentListFrame.origin
            let itemFrame = CGRect(
                origin: CGPoint(x: itemFrameIgnoringSafeArea.origin.x - parentListOffset.x,
                                y: itemFrameIgnoringSafeArea.origin.y - parentListOffset.y),
                size: itemFrameIgnoringSafeArea.size)
            let visible = parentListFrame.intersects(itemFrameIgnoringSafeArea)
            return visible ? itemFrame : nil
        } action: { frame in
            frameUpdated(frame)
        }
    }

    /// Makes a List view ready for use along with ``onItemFrameChanged(listGeometry:_:)``.
    func trackListFrame() -> some View {
        coordinateSpace(.named("ListFrame.Scroll"))
    }
}
