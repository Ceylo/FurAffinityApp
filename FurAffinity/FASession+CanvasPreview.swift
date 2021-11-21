//
//  HTTPDataSource+CanvasPreview.swift
//  FurAffinity
//
//  Created by Ceylo on 16/11/2021.
//

import Foundation
import FAKit
import FAPages

class OfflineFASession: FASession {
    let submissions: [FASubmissionsPage.Submission]
    
    public init(sampleUsername: String, submissions: [FASubmissionsPage.Submission] = []) {
        self.submissions = submissions
        super.init(username: sampleUsername, displayUsername: sampleUsername, cookies: [], dataSource: URLSession.shared)
    }
    
    override func submissions() async -> [FASubmissionsPage.Submission] { submissions }
}

extension OfflineFASession {
    static let `default` = OfflineFASession(sampleUsername: "Demo User", submissions: [
        .init(sid: 44648356,
              url: URL(string: "https://www.furaffinity.net/view/44648356/")!,
              thumbnailUrl: URL(string: "https://t.furaffinity.net/44648356@200-1637084699.jpg")!,
              thumbnailWidthOnHeightRatio: 0.998574972,
              title: "Commission open NOW!",
              author: "hiorou",
              displayAuthor: "Hiorou"),
        .init(sid: 44644268,
              url: URL(string: "https://www.furaffinity.net/view/44644268/")!,
              thumbnailUrl: URL(string: "https://t.furaffinity.net/44644268@300-1637057229.jpg")!,
              thumbnailWidthOnHeightRatio: 1.1006,
              title: "Scary stories",
              author: "annetpeas",
              displayAuthor: "AnnetPeas"),
        .init(sid: 44642258,
              url: URL(string: "https://www.furaffinity.net/view/44642258/")!,
              thumbnailUrl: URL(string: "https://t.furaffinity.net/44642258@400-1637039064.jpg")!,
              thumbnailWidthOnHeightRatio: 1.77231002,
              title: "Halloween-well-cat 18-31 (with link to VID v)",
              author: "rudragon",
              displayAuthor: "RUdragon"),
        .init(sid: 44638371,
              url: URL(string: "https://www.furaffinity.net/view/44638371/")!,
              thumbnailUrl: URL(string: "https://t.furaffinity.net/44638371@400-1637017760.jpg")!,
              thumbnailWidthOnHeightRatio: 2.58585024,
              title: "[OPEN] Adopt Auction - Rasul",
              author: "terriniss",
              displayAuthor: "Terriniss"),
        .init(sid: 44631607,
              url: URL(string: "https://www.furaffinity.net/view/44631607/")!,
              thumbnailUrl: URL(string: "https://t.furaffinity.net/44631607@200-1636991632.jpg")!,
              thumbnailWidthOnHeightRatio: 0.692519962,
              title: "Eorah Pg.205",
              author: "hiorou",
              displayAuthor: "Hiorou")
    ])
}

extension Model {
    static let demo = Model(session: OfflineFASession.default)
}
