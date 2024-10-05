//
//  Kingfisher+FA.swift
//  FurAffinity
//
//  Created by Ceylo on 05/10/2024.
//

import Foundation
import Kingfisher

@MainActor
func FAImage(_ url: URL?) -> KFImage {
    KFImage(url)
        .backgroundDecode()
        .reducePriorityOnDisappear(true)
        .downloader(downloaderWithUserAgent)
        .diskCacheExpiration(.days((7...14).randomElement()!))
        .onFailure { error in
            logger.error("\(error, privacy: .public)")
        }
}

private let downloaderWithUserAgent: ImageDownloader = {
    let downloader = ImageDownloader(name: "FurAffinity Downloader")
    downloader.sessionConfiguration = downloader.sessionConfiguration.withHttpHeadersForFARequests()
    return downloader
}()
