//
//  HTTPDataSource+CanvasPreview.swift
//  FurAffinity
//
//  Created by Ceylo on 16/11/2021.
//

import Foundation
import FAKit

class OfflineFASession: FASession {
    let submissionPreviews: [FASubmissionPreview]
    let notePreviews: [FANotePreview]
    
    public init(sampleUsername: String, submissions: [FASubmissionPreview] = [], notes: [FANotePreview] = []) {
        self.submissionPreviews = submissions
        self.notePreviews = notes
        super.init(username: sampleUsername, displayUsername: sampleUsername, cookies: [], dataSource: URLSession.sharedForFARequests)
    }
    
    override func submissionPreviews() async -> [FASubmissionPreview] { submissionPreviews }
    
    override func submission(for preview: FASubmissionPreview) async -> FASubmission? {
        FASubmission.demo
    }
    
    override func notePreviews() async -> [FANotePreview] { notePreviews }
    
    override func note(for preview: FANotePreview) async -> FANote? {
        return FANote.demo
    }
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
    ], notes: [
        .init(id: 129953494, author: "someuser", displayAuthor: "SomeUser", title: "Another message",
              datetime: "Apr 7, 2022 12:09PM", naturalDatetime: "an hour ago", unread: true,
              noteUrl: URL(string: "https://www.furaffinity.net/msg/pms/1/129953494/#message")!),
        .init(id: 129953262, author: "someuser", displayAuthor: "SomeUser", title: "Title with some spéciäl çhãrāčtęrs",
              datetime: "Apr 7, 2022 11:58AM", naturalDatetime: "an hour ago", unread: false,
              noteUrl: URL(string: "https://www.furaffinity.net/msg/pms/1/129953262/#message")!)
    ])
}

extension Model {
    static let demo = Model(session: OfflineFASession.default)
}

extension FASubmission {
    static let demo: FASubmission = {
        let htmlDescription = "YCH for \n<a href=\"/user/mikazukihellfire\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20211017/mikazukihellfire.gif\" align=\"middle\" title=\"MikazukiHellfire\" alt=\"MikazukiHellfire\">&nbsp;MikazukiHellfire</a>\n<br> \n<br> Medea © \n<a href=\"/user/mikazukihellfire\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20211017/mikazukihellfire.gif\" align=\"middle\" title=\"MikazukiHellfire\" alt=\"MikazukiHellfire\">&nbsp;MikazukiHellfire</a>\n<br> \n<br> \n<br> \n<br> \n<br> *******************************\n<br> * \n<a class=\"auto_link named_url\" href=\"http://ko-fi.com/J3J16KSH\">Feed me with coffee?</a>\n<br> * \n<a class=\"auto_link named_url\" href=\"https://www.furaffinity.net/gallery/annetpeas/\">My Gallery</a>\n<br> * \n<a class=\"auto_link named_url\" href=\"https://twitter.com/AnnetPeas_Art\">Twitter</a>"
        return FASubmission(
            url: URL(string: "https://www.furaffinity.net/view/44188741/")!,
            previewImageUrl: URL(string: "https://t.furaffinity.net/44188741@400-1634411740.jpg")!,
            fullResolutionImageUrl: URL(string: "https://d.furaffinity.net/art/annetpeas/1634411740/1634411740.annetpeas_witch2021__2_fa.png")!,
            author: "annetpeas",
            displayAuthor: "AnnetPeas",
            authorAvatarUrl: URL(string: "https://a.furaffinity.net/1633245638/annetpeas.gif")!,
            title: "Spells and magic",
            htmlDescription: htmlDescription,
            isFavorite: false,
            favoriteUrl: URL(string: "https://www.furaffinity.net/fav/44188741/?key=00f2f5f4c1c7fbfac02147b73d670cac6423ab85")!)
    }()
}

extension FANote {
    static let demo = FANote(author: "someuser", displayAuthor: "SomeUser",
                             title: "RE: Title with some spéciäl çhãrāčtęrs",
                             datetime: "Apr 7th, 2022, 11:58 AM",
                             htmlMessage: "Message with some spéciäl çhãrāčtęrs.\n<br> And a newline!")
}
