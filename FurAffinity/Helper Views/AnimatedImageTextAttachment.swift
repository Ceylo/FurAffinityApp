//
//  AnimatedImageTextAttachment.swift
//  FurAffinity
//
//  Created by Ceylo on 04/07/2026.
//

import UIKit
import Kingfisher

/// A text attachment that hosts a live, animating GIF via a TextKit 2 view
/// provider. The HTML importer flattens `<img>` GIFs into static attachments;
/// swapping those for this subclass restores animation while keeping the
/// original attachment `bounds` (and thus layout/sizing) untouched.
final class AnimatedImageTextAttachment: NSTextAttachment {
    private let gifData: Data

    init(gifData: Data) {
        self.gifData = gifData
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewProvider(
        for parentView: UIView?,
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        let provider = AnimatedGIFAttachmentViewProvider(
            textAttachment: self,
            parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager,
            location: location
        )
        provider.gifData = gifData
        // Keep the original attachment bounds authoritative so sizing is unchanged.
        provider.tracksTextAttachmentViewBounds = false
        return provider
    }
}

final class AnimatedGIFAttachmentViewProvider: NSTextAttachmentViewProvider {
    var gifData: Data?

    override func loadView() {
        // TextKit always calls loadView on the main thread; UIView work needs the
        // main actor, which the override signature doesn't statically carry.
        let data = gifData
        view = MainActor.assumeIsolated {
            let imageView = AnimatedImageView()
            imageView.framePreloadCount = .max // matches FAAnimatedImage config
            imageView.contentMode = .scaleAspectFit
            if let data {
                imageView.image = KingfisherWrapper<KFCrossPlatformImage>.image(
                    data: data,
                    options: ImageCreatingOptions()
                )
            }
            return imageView
        }
    }
}
