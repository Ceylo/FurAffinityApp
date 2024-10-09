//
//  CGSize.swift
//  
//
//  Created by Ceylo on 17/06/2024.
//

import Foundation

extension CGSize {
    public var maxDimension: CGFloat { max(width, height) }
    
    init(_ width: CGFloat, _ height: CGFloat) {
        self.init(width: width, height: height)
    }
    
    func fitting(in size: CGSize) -> CGSize {
        let wRatio = width / size.width
        let hRatio = height / size.height
        
        let maxRatio = max(wRatio, hRatio)
        if maxRatio > 1 {
            return CGSize(
                width: width / maxRatio,
                height: height / maxRatio
            )
        } else {
            return self
        }
    }
}
