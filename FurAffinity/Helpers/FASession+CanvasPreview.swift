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
    
    override func submission(for url: URL) async -> FASubmission? {
        FASubmission.demo
    }
    
    override func nukeSubmissions() async throws {
        print(#function)
    }
    
    override func postComment(on submission: FASubmission, replytoCid: Int?, contents: String) async -> FASubmission? {
        print(#function)
        return submission
    }
    
    override func toggleFavorite(for submission: FASubmission) async -> FASubmission? {
        print(#function)
        return submission
    }
    
    override func notePreviews() async -> [FANotePreview] { notePreviews }
    
    override func note(for preview: FANotePreview) async -> FANote? {
        FANote.demo
    }
    
    override func note(for url: URL) async -> FANote? {
        FANote.demo
    }
    
    override func avatarUrl(for user: String) async -> URL? {
        nil
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
    
    static let empty = OfflineFASession(sampleUsername: "Demo User", submissions: [])
}

extension Model {
    static let demo = Model(session: OfflineFASession.default)
    static let empty = Model(session: OfflineFASession.empty)
}

extension FASubmissionPreview {
    static let demo = FASubmissionPreview(
        sid: 44648356,
        url: URL(string: "https://www.furaffinity.net/view/44648356/")!,
        thumbnailUrl: URL(string: "https://t.furaffinity.net/44648356@200-1637084699.jpg")!,
        thumbnailWidthOnHeightRatio: 0.998574972,
        title: "Commission open NOW!",
        author: "hiorou",
        displayAuthor: "Hiorou"
    )
}

extension FASubmission {
    static let demo: FASubmission = {
        let htmlDescription = "YCH for \n<a href=\"/user/mikazukihellfire\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20211017/mikazukihellfire.gif\" align=\"middle\" title=\"MikazukiHellfire\" alt=\"MikazukiHellfire\">&nbsp;MikazukiHellfire</a>\n<br> \n<br> Medea © \n<a href=\"/user/mikazukihellfire\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20211017/mikazukihellfire.gif\" align=\"middle\" title=\"MikazukiHellfire\" alt=\"MikazukiHellfire\">&nbsp;MikazukiHellfire</a>\n<br> \n<br> \n<br> \n<br> \n<br> *******************************\n<br> * \n<a class=\"auto_link named_url\" href=\"http://ko-fi.com/J3J16KSH\">Feed me with coffee?</a>\n<br> * \n<a class=\"auto_link named_url\" href=\"https://www.furaffinity.net/gallery/annetpeas/\">My Gallery</a>\n<br> * \n<a class=\"auto_link named_url\" href=\"https://twitter.com/AnnetPeas_Art\">Twitter</a>"
        let terrinissAvatarUrl = URL(string: "https://a.furaffinity.net/1616615925/terriniss.gif")!
        let comments: [FASubmission.Comment] = [
            .init(cid: 166652793, displayAuthor: "Terriniss", authorAvatarUrl: terrinissAvatarUrl, datetime: "Aug 11, 2022 09:48 PM", naturalDatetime: "2 months ago",
                  htmlMessage: "BID HERE \n<br> Moon".selfContainedFAHtmlComment, answers: [
                    .init(cid: 166653891, displayAuthor: "Terriniss", authorAvatarUrl: terrinissAvatarUrl, datetime: "Aug 11, 2022 10:58 PM", naturalDatetime: "2 months ago",
                          htmlMessage: "SakuraSlowly (DA) - SB".selfContainedFAHtmlComment, answers: [
                            .init(cid: 166658565, displayAuthor: "Terriniss", authorAvatarUrl: terrinissAvatarUrl, datetime: "Aug 12, 2022 05:16 AM", naturalDatetime: "2 months ago",
                                  htmlMessage: "DeathPanda21 (da) - 55$".selfContainedFAHtmlComment, answers: [])
                          ])
                  ]),
            .init(cid: 166653340, displayAuthor: "RuruDasPippen", authorAvatarUrl: URL(string: "https://a.furaffinity.net/1643948243/rurudaspippen.gif")!,
                  datetime: "Aug 11, 2022 10:23 PM", naturalDatetime: "2 months ago", htmlMessage: "Look at the babies!".selfContainedFAHtmlComment, answers: [])
        ]
        
        return FASubmission(
            url: URL(string: "https://www.furaffinity.net/view/44188741/")!,
            previewImageUrl: URL(string: "https://t.furaffinity.net/44188741@400-1634411740.jpg")!,
            fullResolutionImageUrl: URL(string: "https://d.furaffinity.net/art/annetpeas/1634411740/1634411740.annetpeas_witch2021__2_fa.png")!,
            widthOnHeightRatio: 416 / 600,
            author: "annetpeas",
            displayAuthor: "AnnetPeas",
            authorAvatarUrl: URL(string: "https://a.furaffinity.net/1633245638/annetpeas.gif")!,
            title: "Spells and magic",
            datetime: "Oct 16, 2021 04:15 PM",
            naturalDatetime: "a year ago",
            htmlDescription: htmlDescription,
            isFavorite: false,
            favoriteUrl: URL(string: "https://www.furaffinity.net/fav/44188741/?key=00f2f5f4c1c7fbfac02147b73d670cac6423ab85")!,
            comments: comments)
    }()
}

extension FANote {
    static let demo = FANote(author: "someuser", displayAuthor: "SomeUser",
                             title: "RE: Title with some spéciäl çhãrāčtęrs",
                             datetime: "Apr 7th, 2022, 11:58 AM",
                             naturalDatetime: "8 months ago",
                             htmlMessage: "Message with some spéciäl çhãrāčtęrs.\n<br> And a newline!",
                             answerKey: "84b24b5f34cdfaec56a3679144f6907a98576a57")
}
