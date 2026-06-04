//
//  ImageBlur.swift
//  FurAffinity
//
//  Created by Ceylo on 04/06/2026.
//

import Foundation
import Kingfisher
import UIKit

enum ImageBlur {
    /// Loads the image at `fileURL`, applies a strong blur, JPEG-encodes it, writes
    /// it to a temp file and returns that URL. Returns `nil` on any failure.
    ///
    /// The blur uses Kingfisher's `blurred(withRadius:)`, which is implemented on top
    /// of the Accelerate framework (vImage box convolution) and runs entirely on the
    /// CPU. This is deliberate: this helper runs inside a `BGAppRefreshTask`, and iOS
    /// terminates apps that touch the GPU in the background. `CIGaussianBlur` renders
    /// through a GPU/Metal-backed `CIContext` by default, so it must not be used here.
    static func blurredImageFile(from fileURL: URL, radius: CGFloat = 40) -> URL? {
        guard let image = UIImage(contentsOfFile: fileURL.path(percentEncoded: false)) else {
            logger.error("ImageBlur: failed to load image at \(fileURL)")
            return nil
        }

        let blurred = image.kf.blurred(withRadius: radius)
        guard let data = blurred.jpegData(compressionQuality: 0.9) else {
            logger.error("ImageBlur: failed to JPEG-encode blurred image")
            return nil
        }

        let outURL = URL.temporaryDirectory.appending(component: "blurred-\(fileURL.lastPathComponent)")
        let fileManager = FileManager.default
        do {
            if fileManager.fileExists(atPath: outURL.path(percentEncoded: false)) {
                try fileManager.removeItem(at: outURL)
            }
            try data.write(to: outURL)
            return outURL
        } catch {
            logger.error("ImageBlur: failed to write blurred image: \(error)")
            return nil
        }
    }
}
