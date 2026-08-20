//
//  Sharing.swift
//  FurAffinity
//
//  Created by Ceylo on 12/10/2022.
//

import UIKit

@MainActor
private var foregroundWindow: UIWindow? {
    UIApplication.shared.connectedScenes
        .filter { $0.activationState == .foregroundActive }
        .compactMap { $0 as? UIWindowScene }.first?
        .windows.first
}

@MainActor
func share(_ items: [Any]) {
    let activityVC = UIActivityViewController(activityItems: items,
                                              applicationActivities: nil)

    foregroundWindow?.rootViewController?
        .present(activityVC, animated: true)
}

/// Presents the system "Save to Files" exporter for the given local file URLs.
@MainActor
func exportToFiles(_ urls: [URL]) {
    let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
    foregroundWindow?.rootViewController?
        .present(picker, animated: true)
}
