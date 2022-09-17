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
    public func introspectCollectionView(customize: @escaping (UICollectionView) -> ()) -> some View {
        return inject(UIKitIntrospectionView(
            selector: { introspectionView in
                guard let viewHost = Introspect.findViewHost(from: introspectionView) else {
                    return nil
                }
                return Introspect.previousSibling(containing: UICollectionView.self, from: viewHost)
            },
            customize: customize
        ))
    }
}
