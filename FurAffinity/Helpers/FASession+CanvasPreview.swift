//
//  HTTPDataSource+CanvasPreview.swift
//  FurAffinity
//
//  Created by Ceylo on 16/11/2021.
//

import Foundation
import FAKit

class OfflineFASession: FASession {
    let username: String
    let displayUsername: String
    let submissionPreviews: [FASubmissionPreview]
    let notePreviews: [FANotePreview]
    let notificationPreviews: FANotificationPreviews
    
    nonisolated static func == (lhs: OfflineFASession, rhs: OfflineFASession) -> Bool {
        lhs.username == rhs.username
    }
    
    public init(sampleUsername: String,
                submissions: [FASubmissionPreview],
                notes: [FANotePreview],
                notifications: FANotificationPreviews) {
        self.username = sampleUsername
        self.displayUsername = sampleUsername
        self.submissionPreviews = submissions
        self.notePreviews = notes
        self.notificationPreviews = notifications
    }
    
    func user(for url: URL) async throws -> FAUser {
        await FAUser.demo
    }
    
    func toggleWatch(for user: FAUser) async throws -> FAUser {
        user
    }
    
    func submissionPreviews(from sid: Int?) async -> [FASubmissionPreview] { submissionPreviews }
    
    func deleteSubmissionPreviews(_ previews: [FASubmissionPreview]) async throws {
        print(#function)
    }
    
    func submission(for url: URL) async throws -> FASubmission {
        await FASubmission.demo
    }
    
    func nukeSubmissions() async throws {
        print(#function)
    }
    
    func galleryLike(for url: URL) async throws -> FAUserGalleryLike {
        .init(
            url: url,
            displayAuthor: displayUsername,
            previews: submissionPreviews,
            nextPageUrl: nil,
            folderGroups: [
                .init(title: "Gallery Folders", folders: [
                    .init(title: "Gallery", url: url, isActive: true),
                    .init(title: "Scraps", url: url, isActive: false)
                ])
            ]
        )
    }
    
    func postComment<C: Commentable>(on commentable: C, replytoCid: Int?, contents: String) async -> C {
        print(#function)
        return commentable
    }
    
    func toggleFavorite(for submission: FASubmission) async throws -> FASubmission {
        print(#function)
        return submission
    }
    
    func journals(for url: URL) async throws -> FAUserJournals {
        .init(displayAuthor: displayUsername, journals: [])
    }
    
    func journal(for url: URL) async throws -> FAJournal {
        await FAJournal.demo
    }
    
    func notePreviews(from box: NotesBox) async -> [FANotePreview] { notePreviews }
    
    func note(for url: URL) async throws -> FANote {
        await FANote.demo
    }
    
    func sendNote(toUsername: String, subject: String, message: String) async throws -> Void {
    }
    
    func sendNote(apiKey: String, toUsername: String, subject: String, message: String) async throws -> Void {
    }
    
    func notificationPreviews() async -> FANotificationPreviews {
        notificationPreviews
    }
    
    func deleteSubmissionCommentNotifications(_ notifications: [FANotificationPreview]) async -> FANotificationPreviews {
        notificationPreviews
    }
    
    func deleteJournalCommentNotifications(_ notifications: [FANotificationPreview]) async -> FANotificationPreviews {
        notificationPreviews
    }
    
    func deleteShoutNotifications(_ notifications: [FANotificationPreview]) async -> FANotificationPreviews {
        notificationPreviews
    }
    
    func deleteJournalNotifications(_ notifications: [FANotificationPreview]) async -> FANotificationPreviews {
        notificationPreviews
    }
    
    func nukeAllSubmissionCommentNotifications() async -> FANotificationPreviews {
        notificationPreviews
    }
    
    func nukeAllJournalCommentNotifications() async -> FANotificationPreviews {
        notificationPreviews
    }
    
    func nukeAllShoutNotifications() async -> FANotificationPreviews {
        notificationPreviews
    }
    
    func nukeAllJournalNotifications() async -> FANotificationPreviews {
        notificationPreviews
    }
    
    func watchlist(for username: String, direction: FAWatchlist.WatchDirection) async throws -> FAWatchlist {
        FAWatchlist.demo
    }
}

extension OfflineFASession {
    static let `default` = OfflineFASession(
        sampleUsername: "DemoUser",
        submissions: [
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
            .init(id: 129953494, author: "someuser", displayAuthor: "Some User", title: "Another message",
                  datetime: "Apr 7, 2022 12:09PM", naturalDatetime: "an hour ago", unread: true,
                  noteUrl: URL(string: "https://www.furaffinity.net/msg/pms/1/129953494/#message")!),
            .init(id: 129953262, author: "someuser", displayAuthor: "Some User", title: "Title with some spéciäl çhãrāčtęrs",
                  datetime: "Apr 7, 2022 11:58AM", naturalDatetime: "an hour ago", unread: false,
                  noteUrl: URL(string: "https://www.furaffinity.net/msg/pms/1/129953262/#message")!)
        ], notifications: .init(submissionComments: [
            .init(id: 172177443, author: "furrycount", displayAuthor: "Furrycount", title: "FurAffinity iOS App 1.3 Update",
                  datetime: "on Apr 30, 2023 09:50 PM", naturalDatetime: "a few seconds ago",
                  url: URL(string: "https://www.furaffinity.net/view/49215481/#cid:172177443")!),
            .init(id: 172177425, author: "furrycount", displayAuthor: "Furrycount", title: "FurAffinity iOS App 1.3 Update",
                  datetime: "on Apr 30, 2023 09:49 PM", naturalDatetime: "a minute ago",
                  url: URL(string: "https://www.furaffinity.net/view/49215481/#cid:172177425")!)
        ], journalComments: [
            .init(id: 60479543, author: "ceylo", displayAuthor: "Ceylo", title: "Test",
                  datetime: "on Apr 22, 2024 02:11 PM", naturalDatetime: "couple of minutes ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10528107/#cid:60479543")!)
        ], shouts: [
            .init(
                id: 54237319, author: "ceylo", displayAuthor: "Ceylo", title: "",
                datetime: "on Apr 15, 2023 04:20 PM", naturalDatetime: "some seconds ago",
                url: URL(string: "https://www.furaffinity.net/user/furrycount/#shout-54237319")!
            )
        ], journals: [
            .init(id: 10526001, author: "holt-odium", displayAuthor: "Holt-Odium", title: "📝 3 Slots are available",
                  datetime: "on Apr 14, 2023 08:23 PM", naturalDatetime: "18 hours ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10526001/")!),
            .init(id: 10521084, author: "holt-odium", displayAuthor: "Holt-Odium", title: "Sketch commission are open (115$)",
                  datetime: "on Apr 8, 2023 07:00 PM", naturalDatetime: "a week ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10521084/")!),
            .init(id: 10516170, author: "rudragon", displayAuthor: "RUdragon", title: "UPGRADES ARE OPEN!!! 5",
                  datetime: "on Apr 2, 2023 11:59 PM", naturalDatetime: "12 days ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10516170/")!),
            .init(id: 10512063, author: "ishiru", displayAuthor: "Ishiru", title: "30 minutes before end of auction",
                  datetime: "on Mar 29, 2023 03:33 PM", naturalDatetime: "17 days ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10512063/")!),
            .init(id: 10511753, author: "ishiru", displayAuthor: "Ishiru", title: "one day left",
                  datetime: "on Mar 29, 2023 07:42 AM", naturalDatetime: "17 days ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10511753/")!)
        ]
        )
    )
    
    static let empty = OfflineFASession(sampleUsername: "Demo User", submissions: [], notes: [], notifications: .init())
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

extension FAUserGalleryLike.FolderGroup {
    static let demo: [FAUserGalleryLike.FolderGroup] = [
        .init(title: "Gallery Folders", folders: [
            .init(title: "Main Gallery", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/")!, isActive: true),
            .init(title: "Scraps", url: URL(string: "https://www.furaffinity.net/scraps/tiaamaito/")!, isActive: false)
        ]),
        .init(title: "Personal", folders: [
            .init(title: "Chuvareu", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/147920/Chuvareu")!, isActive: false),
            .init(title: "Chuvareu Comic (archieved)", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/292599/Chuvareu-Comic-archieved")!, isActive: false),
            .init(title: "Bakemono Family", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/418988/Bakemono-Family")!, isActive: false),
            .init(title: "chars as animals", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/456419/chars-as-animals")!, isActive: false),
            .init(title: "the tiniest lord", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/566887/the-tiniest-lord")!, isActive: false),
            .init(title: "Ribbon Pooch & Co", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/566888/Ribbon-Pooch-Co")!, isActive: false),
            .init(title: "Kijani", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/566890/Kijani")!, isActive: false),
            .init(title: "Digital Pack", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/566891/Digital-Pack")!, isActive: false),
        ]),
        .init(title: "Closed Species", folders: [
            .init(title: "Sushi Dogs", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/566883/Sushi-Dogs")!, isActive: false),
            .init(title: "Griffia", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/566884/Griffia")!, isActive: false),
            .init(title: "Memory Keepers", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/720355/Memory-Keepers")!, isActive: false),
        ]),
        .init(title: "for Sale", folders: [
            .init(title: "P2U", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/473101/P2U")!, isActive: false),
            .init(title: "Adopts", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/473103/Adopts")!, isActive: false),
            .init(title: "Traditional Pieces", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/495402/Traditional-Pieces")!, isActive: false),
            .init(title: "Other", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/547857/Other")!, isActive: false),
            .init(title: "Art Prints", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/684620/Art-Prints")!, isActive: false),
        ]),
        .init(title: "Patreon", folders: [
            .init(title: "2016", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/135452/2016")!, isActive: false),
            .init(title: "2017", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/297815/2017")!, isActive: false),
            .init(title: "2018", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/459438/2018")!, isActive: false),
            .init(title: "2019", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/613283/2019")!, isActive: false),
            .init(title: "2020", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/754413/2020")!, isActive: false),
            .init(title: "2021", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/937613/2021")!, isActive: false),
        ]),
        .init(title: "Commissions", folders: [
            .init(title: "standard (cell shading)", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/147923/standard-cell-shading")!, isActive: false),
            .init(title: "clear (soft shading)", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/147924/clear-soft-shading")!, isActive: false),
            .init(title: "basic (base colors)", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/147925/basic-base-colors")!, isActive: false),
            .init(title: "reference sheet", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/147927/reference-sheet")!, isActive: false),
            .init(title: "YCH", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/147928/YCH")!, isActive: false),
            .init(title: "telegram stickers", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/415109/telegram-stickers")!, isActive: false),
            .init(title: "special", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/578261/special")!, isActive: false),
            .init(title: "old works", url: URL(string: "https://www.furaffinity.net/gallery/tiaamaito/folder/147929/old-works")!, isActive: false),
        ])
    ]
}

extension FAComment {
    static let terrinissAvatarUrl = URL(string: "https://a.furaffinity.net/1616615925/terriniss.gif")!
    static var demo: [FAComment] {
        get async {
            try! await [
                .visible(.init(
                    cid: 166652793, author: "terriniss", displayAuthor: "Terriniss", datetime: "Aug 11, 2022 09:48 PM", naturalDatetime: "2 months ago",
                    message: .init(FAHTML: "BID HERE \n<br> Moon".selfContainedFAHtmlComment), answers: [
                        .visible(.init(
                            cid: 166653891, author: "terriniss", displayAuthor: "Terriniss", datetime: "Aug 11, 2022 10:58 PM", naturalDatetime: "2 months ago",
                            message: .init(FAHTML: "SakuraSlowly (DA) - SB".selfContainedFAHtmlComment), answers: [
                                .visible(.init(
                                    cid: 166658565, author: "terriniss", displayAuthor: "Terriniss", datetime: "Aug 12, 2022 05:16 AM", naturalDatetime: "2 months ago",
                                    message: .init(FAHTML: "DeathPanda21 (da) - 55$".selfContainedFAHtmlComment), answers: [])
                                )]))
                    ])),
                .visible(.init(
                    cid: 166653340, author: "rurudaspippen", displayAuthor: "RuruDasPippen",
                    datetime: "Aug 11, 2022 10:23 PM", naturalDatetime: "2 months ago", message: .init(FAHTML: "Look at the babies!".selfContainedFAHtmlComment), answers: []
                ))
            ]
        }
    }
    
    static var demoHidden: [FAComment] {
        get async {
            try! await [
                .hidden(.init(
                    cid: 171145030,
                    message: .init(FAHTML: "[deleted]".selfContainedFAHtmlComment),
                    answers: [
                        .visible(.init(
                            cid: 166653340, author: "rurudaspippen", displayAuthor: "RuruDasPippen",
                            datetime: "Aug 11, 2022 10:23 PM", naturalDatetime: "2 months ago", message: .init(FAHTML: "Look at the babies!".selfContainedFAHtmlComment), answers: []
                        ))
                    ]
                ))
            ]
        }
    }
}

extension FASubmission {
    static var demo: FASubmission {
        get async {
            let htmlDescription = "YCH for \n<a href=\"/user/mikazukihellfire\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20211017/mikazukihellfire.gif\" align=\"middle\" title=\"MikazukiHellfire\" alt=\"MikazukiHellfire\">&nbsp;MikazukiHellfire</a>\n<br> \n<br> Medea © \n<a href=\"/user/mikazukihellfire\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20211017/mikazukihellfire.gif\" align=\"middle\" title=\"MikazukiHellfire\" alt=\"MikazukiHellfire\">&nbsp;MikazukiHellfire</a>\n<br> \n<br> \n<br> \n<br> \n<br> *******************************\n<br> * \n<a class=\"auto_link named_url\" href=\"http://ko-fi.com/J3J16KSH\">Feed me with coffee?</a>\n<br> * \n<a class=\"auto_link named_url\" href=\"https://www.furaffinity.net/gallery/annetpeas/\">My Gallery</a>\n<br> * \n<a class=\"auto_link named_url\" href=\"https://twitter.com/AnnetPeas_Art\">Twitter</a>"
            
            return await FASubmission(
                url: URL(string: "https://www.furaffinity.net/view/44188741/")!,
                previewImageUrl: URL(string: "https://t.furaffinity.net/44188741@400-1634411740.jpg")!,
                fullResolutionMediaUrl: URL(string: "https://d.furaffinity.net/art/annetpeas/1634411740/1634411740.annetpeas_witch2021__2_fa.png")!,
                widthOnHeightRatio: 416 / 600,
                metadata: FASubmission.Metadata(
                    title: "Spells and magic",
                    author: "annetpeas",
                    displayAuthor: "AnnetPeas",
                    datetime: "Oct 16, 2021 04:15 PM",
                    naturalDatetime: "a year ago",
                    viewCount: 755,
                    commentCount: 3,
                    favoriteCount: 72,
                    rating: .general,
                    category: "Artwork (Digital) / All",
                    species: "Unspecified / Any",
                    size: "888 x 1280",
                    fileSize: "949.8 kB",
                    keywords: ["mikazukihellfire", "medea", "female", "cute", "chibi", "annetpeas", "halloween", "witch", "grimoire", "magic", "books"],
                    folders: [
                        .init(
                            title: "My arts - 2021",
                            url: URL(string: "https://www.furaffinity.net/gallery/annetpeas/folder/910706/2021/")!,
                            isActive: false
                        ),
                        .init(
                            title: "My arts - 🎃 Halloween Witches!!",
                            url: URL(string: "https://www.furaffinity.net/gallery/annetpeas/folder/1037607/Halloween-Witches/")!,
                            isActive: false
                        )
                    ]
                ),
                description: try! AttributedString(FAHTML: htmlDescription.selfContainedFAHtmlSubmission),
                isFavorite: false,
                favoriteUrl: URL(string: "https://www.furaffinity.net/fav/44188741/?key=00f2f5f4c1c7fbfac02147b73d670cac6423ab85")!,
                comments: FAComment.demo,
                targetCommentId: nil,
                acceptsNewComments: true
            )
        }
    }
}

extension FAJournal {
    static var demo: FAJournal {
        get async {
            let htmlDescription = """
what you will need to get one.\n<br> - if you got a sketch you can get an upgrade.\n<br> -comment on this Journal to get in line(ill work down the line and work in that order)\n<br> -make sure you have the funds to get a spot.\n<br> -if you have one more then one sketch you can have 3 at the most i can upgrade ( make sure you have the funds if your doing more then one)\n<br> -ill note you to get the ref and info to upgrade your pic. the farther your in line the longer will take to get to you, so PLZ try put aside the funds till i get to you in line.\n<br> -you will be paying $75 or more depending on what you want done.\n<br> for just you OC and no BG will $75 per OC.\n<br> BG and or extra stuff added will be $100 more or less.\n<br> \n<br> after this will go back to sketches then back to upgrades.\n<br> \n<br> depending on how much the person asks could take me more or less time to get to the next one in line.\n<br> so PLZ wait for not to get your info.\n<br> \n<br> GOOD LUCK TO EVERYONE.\n<br> \n<br> \n<br> 1. \n<a href=\"/user/fukothenimbat\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20230416/fukothenimbat.gif\" align=\"middle\" title=\"fukothenimbat\" alt=\"fukothenimbat\">&nbsp;fukothenimbat</a>\n<br> \n<br> 2. \n<a href=\"/user/zacharywulf\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20230416/zacharywulf.gif\" align=\"middle\" title=\"zacharywulf\" alt=\"zacharywulf\">&nbsp;zacharywulf</a>\n<br> \n<br> 3. \n<a href=\"/user/leacrea\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20230416/leacrea.gif\" align=\"middle\" title=\"leacrea\" alt=\"leacrea\">&nbsp;leacrea</a>\n<br> \n<br> 4. \n<a href=\"/user/thegrapedemon\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20230416/thegrapedemon.gif\" align=\"middle\" title=\"thegrapedemon\" alt=\"thegrapedemon\">&nbsp;thegrapedemon</a>\n<br> \n<br> 5. \n<a href=\"/user/shadoweddraco\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20230416/shadoweddraco.gif\" align=\"middle\" title=\"shadoweddraco\" alt=\"shadoweddraco\">&nbsp;shadoweddraco</a>\n<br> \n<br> for not this will be the last one then going back to sketches then maybe open one more then back to one more upgrade but will see how things go.
"""
            
            return try! await FAJournal(
                url: URL(string: "https://www.furaffinity.net/journal/10516170/")!,
                author: "rudragon",
                displayAuthor: "RUdragon",
                title: "UPGRADES ARE OPEN!!! 5",
                datetime: "Apr 2, 2023 11:59 PM",
                naturalDatetime: "2 weeks ago",
                description: AttributedString(FAHTML: htmlDescription.selfContainedFAHtmlSubmission),
                comments: FAComment.demo,
                targetCommentId: nil,
                acceptsNewComments: true
            )
        }
    }
}

extension FANote {
    static var demo: FANote {
        get async {
            try! await FANote(
                url: URL(string: "https://www.furaffinity.net/msg/pms/1/123456789/#message")!,
                author: "someuser", displayAuthor: "Some User",
                title: "RE: Title with some spéciäl çhãrāčtęrs",
                datetime: "Apr 7th, 2022, 11:58 AM",
                naturalDatetime: "8 months ago",
                message: AttributedString(FAHTML: "Message with some spéciäl çhãrāčtęrs.\n<br> And a newline!".selfContainedFAHtmlSubmission),
                messageWithoutWarning: AttributedString(FAHTML: "Message with some spéciäl çhãrāčtęrs.\n<br> And a newline!".selfContainedFAHtmlSubmission),
                answerKey: "84b24b5f34cdfaec56a3679144f6907a98576a57",
                answerPlaceholderMessage: """


—————————
original post by Some User (@someuser):

Message with some spéciäl çhãrāčtęrs.\n<br> And a newline!
"""
            )
        }
    }
}

extension FAUser {
    private static let htmlDescription = """
<code class=\"bbcode bbcode_center\"> <a href=\"/user/vampireknightlampleftplz\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/vampireknightlampleftplz.gif\" align=\"middle\" title=\"vampireknightlampleftplz\" alt=\"vampireknightlampleftplz\"></a> <a href=\"/user/hawthornbloodmoon\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/hawthornbloodmoon.gif\" align=\"middle\" title=\"hawthornbloodmoon\" alt=\"hawthornbloodmoon\"></a> <a href=\"/user/vampireknightlamprightplz\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/vampireknightlamprightplz.gif\" align=\"middle\" title=\"vampireknightlamprightplz\" alt=\"vampireknightlamprightplz\"></a> <br> <br> <h4 class=\"bbcode bbcode_h4\"> ∼ 👣 𝙃𝙖𝙫𝙚 𝙖 𝙣𝙞𝙘𝙚 𝙙𝙖𝙮, 𝙩𝙧𝙖𝙫𝙚𝙡𝙚𝙧 <br> 𝘾𝙤𝙢𝙚 𝙘𝙡𝙤𝙨𝙚𝙧 𝙖𝙣𝙙 𝙄\'𝙡𝙡 𝙨𝙝𝙤𝙬 𝙮𝙤𝙪 𝙞𝙣𝙘𝙧𝙚𝙙𝙞𝙗𝙡𝙚 𝙗𝙚𝙖𝙨𝙩𝙨 🐾 ∼ </h4><br> \n <hr class=\"bbcode bbcode_hr\"> <br> My name is <strong class=\"bbcode bbcode_b\">Terriniss.</strong> <br> Briefly - <strong class=\"bbcode bbcode_b\">Tira.</strong> <br> <br> <span class=\"bbcode\" style=\"color: #C92A2A;\">▸▹</span> 26 y.o. <span class=\"bbcode\" style=\"color: #000000;\">●</span> RU/ENG <span class=\"bbcode\" style=\"color: #000000;\">●</span> SFW <span class=\"bbcode\" style=\"color: #000000;\">●</span> Digital artist <span class=\"bbcode\" style=\"color: #C92A2A;\">◂◃</span><br> <span class=\"bbcode\" style=\"color: #C92A2A;\">▸▹</span> I\'m glad to see you here! <span class=\"bbcode\" style=\"color: #C92A2A;\">◂◃</span><br> <br> <sub class=\"bbcode bbcode_sub\"> 🌑 My main job here is creating fantasy creatures.<br> Mystical and dark themes are my favorite, but sometimes, on the contrary, I want to create something light.<br> I\'m trying to make the creature as alive as possible emotionally, <br> I want you to see his emotions when you look into his face, <br> or at the expressions of his body. And so that when I looked into his face, I could see them too.<br> I\'m glad when I can do it. And I\'m glad if you notice it. 🌕</sub> <br> <br> <span class=\"bbcode\" style=\"color: #C92A2A;\">☘</span> Thank you for your attention to my work. This is really important to me! <span class=\"bbcode\" style=\"color: #C92A2A;\">☘</span><br> <br> \n <hr class=\"bbcode bbcode_hr\"> <br> <u class=\"bbcode bbcode_u\"> My second account, for YCHes </u> <br> <a href=\"/user/terriniss-yches\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/terriniss-yches.gif\" align=\"middle\" title=\"terriniss-yches\" alt=\"terriniss-yches\"></a><br> <br> <u class=\"bbcode bbcode_u\"> My dear friends </u> <br> <a href=\"/user/obsidianna\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/obsidianna.gif\" align=\"middle\" title=\"obsidianna\" alt=\"obsidianna\"></a> <a href=\"/user/jackdeath11\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/jackdeath11.gif\" align=\"middle\" title=\"jackdeath11\" alt=\"jackdeath11\"></a> <a href=\"/user/draynd\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/draynd.gif\" align=\"middle\" title=\"draynd\" alt=\"draynd\"></a> <a href=\"/user/sapfirachib\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/sapfirachib.gif\" align=\"middle\" title=\"sapfirachib\" alt=\"sapfirachib\"></a> <a href=\"/user/noxor\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/noxor.gif\" align=\"middle\" title=\"noxor\" alt=\"noxor\"></a> <a href=\"/user/vetka\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/vetka.gif\" align=\"middle\" title=\"vetka\" alt=\"vetka\"></a> <a href=\"/user/rurudaspippen\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/rurudaspippen.gif\" align=\"middle\" title=\"rurudaspippen\" alt=\"rurudaspippen\"></a> <a href=\"/user/innart\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/innart.gif\" align=\"middle\" title=\"innart\" alt=\"innart\"></a> <a href=\"/user/chefraven\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/chefraven.gif\" align=\"middle\" title=\"chefraven\" alt=\"chefraven\"></a><br> <sub class=\"bbcode bbcode_sub\"> (Sorry if I forgot to mention anyone here)</sub> <br> <br> \n <hr class=\"bbcode bbcode_hr\"> <br> <span class=\"bbcode\" style=\"color: #000000;\">🕷</span> <u class=\"bbcode bbcode_u\"><span class=\"bbcode\" style=\"color: #EB3131;\"><strong class=\"bbcode bbcode_b\">Art-status</strong></span></u> <span class=\"bbcode\" style=\"color: #000000;\">🕷</span> <br> <span class=\"bbcode\" style=\"color: #000000;\">╭</span><span class=\"bbcode\" style=\"color: #131313;\">━</span><span class=\"bbcode\" style=\"color: #262626;\">━</span><span class=\"bbcode\" style=\"color: #393939;\">━</span><span class=\"bbcode\" style=\"color: #4C4C4C;\">━</span><span class=\"bbcode\" style=\"color: #606060;\">━</span><span class=\"bbcode\" style=\"color: #737373;\">━</span><span class=\"bbcode\" style=\"color: #868686;\">━</span><span class=\"bbcode\" style=\"color: #999999;\">━</span><span class=\"bbcode\" style=\"color: #ADADAD;\">━</span><span class=\"bbcode\" style=\"color: #999A99;\">━</span><span class=\"bbcode\" style=\"color: #868786;\">━</span><span class=\"bbcode\" style=\"color: #737473;\">━</span><span class=\"bbcode\" style=\"color: #606160;\">━</span><span class=\"bbcode\" style=\"color: #4C4E4C;\">━</span><span class=\"bbcode\" style=\"color: #393B39;\">━</span><span class=\"bbcode\" style=\"color: #262826;\">━</span><span class=\"bbcode\" style=\"color: #131513;\">━</span><span class=\"bbcode\" style=\"color: #000300;\">╮</span><br> <strong class=\"bbcode bbcode_b\">Commissions</strong> - open:<br> - headshot (w/o detailed bg)<br> - Haflbody (w/o detailed bg)<br> - custom design.<br> <br> <strong class=\"bbcode bbcode_b\">Collabs</strong> - maybe<br> <br> <strong class=\"bbcode bbcode_b\">Requests</strong> - no :&lt;<br> <span class=\"bbcode\" style=\"color: #000000;\">╰</span><span class=\"bbcode\" style=\"color: #131313;\">━</span><span class=\"bbcode\" style=\"color: #262626;\">━</span><span class=\"bbcode\" style=\"color: #393939;\">━</span><span class=\"bbcode\" style=\"color: #4C4C4C;\">━</span><span class=\"bbcode\" style=\"color: #606060;\">━</span><span class=\"bbcode\" style=\"color: #737373;\">━</span><span class=\"bbcode\" style=\"color: #868686;\">━</span><span class=\"bbcode\" style=\"color: #999999;\">━</span><span class=\"bbcode\" style=\"color: #ADADAD;\">━</span><span class=\"bbcode\" style=\"color: #999A99;\">━</span><span class=\"bbcode\" style=\"color: #868786;\">━</span><span class=\"bbcode\" style=\"color: #737473;\">━</span><span class=\"bbcode\" style=\"color: #606160;\">━</span><span class=\"bbcode\" style=\"color: #4C4E4C;\">━</span><span class=\"bbcode\" style=\"color: #393B39;\">━</span><span class=\"bbcode\" style=\"color: #262826;\">━</span><span class=\"bbcode\" style=\"color: #131513;\">━</span><span class=\"bbcode\" style=\"color: #000300;\">╯</span><br> <br> <a class=\"auto_link named_url\" href=\"https://www.deviantart.com/terriniss/\">DeviantArt</a> <br> <br> <h5 class=\"bbcode bbcode_h5\"><span class=\"bbcode\" style=\"color: #C92A2A;\">🕷</span> <a class=\"auto_link named_url\" href=\"https://www.patreon.com/Terriniss/id0\">PATREON</a> <span class=\"bbcode\" style=\"color: #C92A2A;\">🕷</span><br> <span class=\"bbcode\" style=\"color: #C92A2A;\">🕷</span> (Here you can see sketches and works that will NOT be uploaded to other galleries!) <span class=\"bbcode\" style=\"color: #C92A2A;\">🕷</span></h5> <br> <br> <sub class=\"bbcode bbcode_sub\"> P.S. Unfortunately, English is not my native language. I often have to communicate through a translator. Nevertheless, I will be glad to talk to any of you!</sub> </code>
""".selfContainedFAHtmlSubmission
    
    static var demo: FAUser {
        get async {
            try! await FAUser(
                name: "demo",
                displayName: "Demo Long Name",
                bannerUrl: URL(string: "https://www.furaffinity.net/themes/beta/img/banners/logo/fa-banner-winter.jpg")!,
                htmlDescription: htmlDescription,
                shouts: [
                    .visible(.init(
                        cid: 54569442, author: "sadisticss", displayAuthor: "Sadisticss",
                        datetime: "Jul 29, 2023 10:16 PM", naturalDatetime: "a month ago",
                        message: .init(FAHTML: "Hola, dear! U have nice gallery &lt;3".selfContainedFAHtmlComment),
                        answers: []
                    )),
                    .visible(.init(
                        cid: 53766730, author: "mostevilpupper", displayAuthor: "MostEvilPupper",
                        datetime: "Dec 6, 2022 03:46 AM", naturalDatetime: "9 months ago",
                        message: .init(FAHTML: "An absolutely amazing artist".selfContainedFAHtmlComment),
                        answers: []
                    ))
                ],
                targetShoutId: nil,
                watchData: WatchData(watchUrl: URL(string: "https://www.furaffinity.net/watch/furrycount/?key=c11e718bd61ecbfad8750b76135052f90ea84026")!)
            )
        }
    }
}

extension FAUserJournals {
    static let empty: Self = .init(
        displayAuthor: "tiaamaito",
        journals: []
    )
    
    static let demo: Self = .init(
        displayAuthor: "tiaamaito",
        journals: [
            .init(id: 10954574, title: "I'll resume posting art!",
                  datetime: "Sep 14, 2024 03:17 AM", naturalDatetime: "a month ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10954574/")!),
            .init(id: 10893232, title: "fullbody commissions (CLOSED)",
                  datetime: "Jun 23, 2024 07:14 PM", naturalDatetime: "3 months ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10893232/")!),
            .init(id: 10877414, title: "Pride themed group YCH closed!!",
                  datetime: "Jun 1, 2024 03:03 AM", naturalDatetime: "4 months ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10877414/")!),
            .init(id: 10815815, title: "Change on commissions!",
                  datetime: "Mar 2, 2024 03:13 AM", naturalDatetime: "7 months ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10815815/")!),
            .init(id: 10691323, title: "Follow me on BlueSky! (and other places)",
                  datetime: "Sep 20, 2023 02:50 AM", naturalDatetime: "a year ago",
                  url: URL(string: "https://www.furaffinity.net/journal/10691323/")!),
        ]
    )
}

extension FAWatchlist {
    static let demo = FAWatchlist(
        currentUser: .init(name: "demouser", displayName: "DemoUser"),
        watchDirection: .watching,
        users: [
            .init(name: "-haunter-", displayName: "-Haunter-"),
            .init(name: "-karasu-", displayName: "-Karasu-"),
            .init(name: "-mlady-", displayName: "-Mlady-"),
            .init(name: "-soda-", displayName: "-SODA-"),
            .init(name: "acidic-commissions", displayName: "Acidic-commissions"),
            .init(name: "adelaherz", displayName: "AdelaHerz"),
            .init(name: "aivoree", displayName: "Aivoree"),
            .init(name: "alectorfencer", displayName: "AlectorFencer"),
            .init(name: "ashennite", displayName: "AshenNite"),
            .init(name: "balaa", displayName: "balaa"),
            .init(name: "balans", displayName: "Balans"),
            .init(name: "bariesuterram", displayName: "BariesuTerram"),
            .init(name: "blackyblack", displayName: "BlackyBlack"),
            .init(name: "blade13015", displayName: "Blade13015"),
            .init(name: "brightopticeyes", displayName: "BrightOpticEyes"),
            .init(name: "bubblewolf", displayName: "BubbleWolf"),
            .init(name: "caraid", displayName: "Caraid"),
            .init(name: "centradragon", displayName: "Centradragon"),
            .init(name: "checkhoff", displayName: "Checkhoff"),
            .init(name: "chicken-scratch", displayName: "Chicken-Scratch"),
            .init(name: "corycatte", displayName: "corycatte"),
            .init(name: "cottagemoss", displayName: "CottageMoss"),
            .init(name: "crustypunkychimera", displayName: "CrustypunkyChimera"),
            .init(name: "dalekfell", displayName: "DalekFell"),
            .init(name: "darkgem", displayName: "darkgem"),
            .init(name: "darktiggy", displayName: "darktiggy"),
            .init(name: "dablazor", displayName: "Da_Blazor"),
            .init(name: "deltaw0lf1929", displayName: "DeltaW0lf1929"),
            .init(name: "dimonis", displayName: "Dimonis"),
            .init(name: "dj-skully", displayName: "Dj-Skully"),
            .init(name: "dolly", displayName: "Dolly"),
            .init(name: "dranenngan", displayName: "Dranenngan"),
            .init(name: "elenasadko", displayName: "ElenaSadko"),
            .init(name: "felangrey", displayName: "FelanGrey"),
            .init(name: "firefeathers", displayName: "Firefeathers"),
            .init(name: "fleurman13", displayName: "Fleurman13"),
            .init(name: "floo", displayName: "floO"),
            .init(name: "floriada", displayName: "Floriada"),
            .init(name: "fluffymuttdog", displayName: "fluffymuttdog"),
            .init(name: "flutesong", displayName: "Flutesong"),
            .init(name: "forgeddarkness", displayName: "ForgedDarkness"),
            .init(name: "foxyfembo1", displayName: "FoxyFemBo1"),
            .init(name: "free-opium", displayName: "Free-Opium"),
            .init(name: "henjikotetsu", displayName: "HenjiKotetsu"),
            .init(name: "honovy", displayName: "Honovy"),
            .init(name: "hontoriel", displayName: "Hontoriel"),
            .init(name: "hun", displayName: "Hun"),
            .init(name: "immaturecontent", displayName: "ImmatureContent"),
            .init(name: "innart", displayName: "inn_art"),
            .init(name: "jackdeath11", displayName: "JackDeath11"),
            .init(name: "jackthewerewolf", displayName: "JacktheWerewolf"),
            .init(name: "juliathedragoncat", displayName: "JuliaTheDragonCat"),
            .init(name: "jyirilazybones", displayName: "JyiriLazybones"),
            .init(name: "kageichi", displayName: "Kageichi"),
            .init(name: "kaji", displayName: "Kaji"),
            .init(name: "kaptainspicy", displayName: "Kaptain_spicy"),
            .init(name: "kenket", displayName: "Kenket"),
            .init(name: "kirawra", displayName: "KiRAWRa"),
            .init(name: "kotyami.art", displayName: "kotyami.art"),
            .init(name: "ksejl", displayName: "ksejl"),
            .init(name: "lepricon", displayName: "Lepricon"),
            .init(name: "levelviolet", displayName: "LevelViolet"),
            .init(name: "lhyrra", displayName: "Lhyrra"),
            .init(name: "luch", displayName: "Luch"),
            .init(name: "maleklattesh", displayName: "MalekLattesh"),
            .init(name: "motolog", displayName: "Motolog"),
            .init(name: "nomax", displayName: "Nomax"),
            .init(name: "nordwolfe", displayName: "nordwolfe"),
            .init(name: "novaskitten", displayName: "NovaSkitten"),
            .init(name: "noxor", displayName: "Noxor"),
            .init(name: "obsidianna", displayName: "Obsidianna"),
            .init(name: "osariaallyeid", displayName: "OsariaAllyeid"),
            .init(name: "ottobergen", displayName: "ottobergen"),
            .init(name: "ottomonpyre", displayName: "OttoMonpyre"),
            .init(name: "pacelic", displayName: "Pacelic"),
            .init(name: "pawbz", displayName: "Pawbz"),
            .init(name: "pervysensei", displayName: "PervySensei"),
            .init(name: "poprocker566", displayName: "poprocker566"),
            .init(name: "pshe", displayName: "Pshe"),
            .init(name: "queenofcroia", displayName: "QueenOfCroia"),
            .init(name: "racoonwolf", displayName: "racoonwolf"),
            .init(name: "raharu95", displayName: "Raharu95"),
            .init(name: "rekkz", displayName: "Rekkz"),
            .init(name: "rivalmit", displayName: "rivalmit"),
            .init(name: "rymio", displayName: "Rymio"),
            .init(name: "sapfirachib", displayName: "SapfiraChib"),
            .init(name: "seskata", displayName: "seskata"),
            .init(name: "sheebs", displayName: "Sheebs"),
            .init(name: "sheepishabbey", displayName: "SheepishAbbey"),
            .init(name: "sidgi", displayName: "Sidgi"),
            .init(name: "silverarma", displayName: "Silverarma"),
            .init(name: "silverbloodwolf98", displayName: "silverbloodwolf98"),
            .init(name: "silverfox5213", displayName: "silverfox5213"),
            .init(name: "sixfoot", displayName: "sixfoot"),
            .init(name: "skiaskai", displayName: "SkiaSkai"),
            .init(name: "slavawl", displayName: "SlavaWL"),
            .init(name: "slumphy", displayName: "slumphy"),
            .init(name: "smileeeeeee", displayName: "Smileeeeeee"),
            .init(name: "soongdae", displayName: "SoongDae"),
            .init(name: "stigmata", displayName: "stigmata"),
            .init(name: "stretchsnake", displayName: "Stretchsnake"),
            .init(name: "tacklebox", displayName: "tacklebox"),
            .init(name: "teckelarts", displayName: "Teckelarts"),
            .init(name: "terrygrimm", displayName: "Terry_Grimm"),
            .init(name: "thanshuhai", displayName: "thanshuhai"),
            .init(name: "tjtiger", displayName: "Tj_Tiger"),
            .init(name: "ursa.h", displayName: "Ursa.H"),
            .init(name: "victoranne", displayName: "Victor_Anne"),
            .init(name: "viiburnum", displayName: "Viiburnum"),
            .init(name: "vincentlim", displayName: "VincentLim"),
            .init(name: "vinrage", displayName: "VinRage"),
            .init(name: "weare...sexybears...", displayName: "We_are...Sexy_bearS..."),
            .init(name: "whitemantis", displayName: "WhiteMantis"),
            .init(name: "wolf12345", displayName: "wolf12345"),
            .init(name: "xepxyu", displayName: "xepxyu"),
            .init(name: "xerxis", displayName: "Xerxis"),
            .init(name: "zemus98", displayName: "Zemus98"),
            .init(name: "zullkharn", displayName: "ZullKharn"),
            .init(name: "~inkyenigma~", displayName: "~InkyEnigma~"),
            .init(name: "~rizonik~", displayName: "~RIZONIK~")
        ],
        nextPageUrl: nil
    )
}
