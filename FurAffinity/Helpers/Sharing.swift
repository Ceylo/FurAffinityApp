//
//  Sharing.swift
//  FurAffinity
//
//  Created by Ceylo on 12/10/2022.
//

import UIKit

@MainActor
func share(_ items: [Any]) {
    let activityVC = UIActivityViewController(activityItems: items,
                                              applicationActivities: nil)
    
    let window = UIApplication.shared.connectedScenes
        .filter { $0.activationState == .foregroundActive }
        .compactMap { $0 as? UIWindowScene }.first?
        .windows.first
    
    window?.rootViewController?
        .present(activityVC, animated: true)
}
