//
//  QuickLookPreview.swift
//  FurAffinity
//
//  Created by Ceylo on 21/06/2026.
//

import SwiftUI
import QuickLook

/// Presents a local file in a native QuickLook preview, suitable for a sheet.
struct QuickLookPreview: UIViewControllerRepresentable {
    let fileUrl: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(fileUrl: fileUrl)
    }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {
        context.coordinator.fileUrl = fileUrl
        controller.reloadData()
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var fileUrl: URL

        init(fileUrl: URL) {
            self.fileUrl = fileUrl
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            fileUrl as NSURL
        }
    }
}
