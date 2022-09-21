//
//  View+Introspection.swift
//  FurAffinity
//
//  Created by Ceylo on 17/09/2022.
//

import SwiftUI
import Introspect
import UIKit

extension View {
    public func introspectScrollViewOnList(customize: @escaping (UIScrollView) -> ()) -> some View {
        return inject(UIKitIntrospectionView(
            selector: { introspectionView in
                guard let viewHost = Introspect.findViewHost(from: introspectionView) else {
                    return nil
                }
                return Introspect.previousSibling(containing: UIScrollView.self, from: viewHost)
            },
            customize: customize
        ))
    }
}
