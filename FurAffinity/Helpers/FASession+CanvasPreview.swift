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
    
    let notificationPreviews: NotificationPreviews
    
    public init(sampleUsername: String,
                submissions: [FASubmissionPreview],
                notes: [FANotePreview],
                notifications: NotificationPreviews) {
        self.submissionPreviews = submissions
        self.notePreviews = notes
        self.notificationPreviews = notifications
        super.init(username: sampleUsername, displayUsername: sampleUsername, cookies: [], dataSource: URLSession.sharedForFARequests)
    }
    
    override func user(for url: URL) async -> FAUser? {
        FAUser.demo
    }
    
    override func submissionPreviews() async -> [FASubmissionPreview] { submissionPreviews }
    
    override func submission(for url: URL) async -> FASubmission? {
        FASubmission.demo
    }
    
    override func nukeSubmissions() async throws {
        print(#function)
    }
    
    override func postComment<C: Commentable>(on commentable: C, replytoCid: Int?, contents: String) async -> C? {
        print(#function)
        return commentable
    }
    
    override func toggleFavorite(for submission: FASubmission) async -> FASubmission? {
        print(#function)
        return submission
    }
    
    override func notePreviews() async -> [FANotePreview] { notePreviews }
    
    override func note(for url: URL) async -> FANote? {
        FANote.demo
    }
    
    override func notificationPreviews() async -> NotificationPreviews {
        notificationPreviews
    }
    
    override func deleteSubmissionCommentNotifications(_ notifications: [FASubmissionCommentNotificationPreview]) async -> NotificationPreviews {
        notificationPreviews
    }
    
    override func deleteJournalNotifications(_ notifications: [FAJournalNotificationPreview]) async -> NotificationPreviews {
        notificationPreviews
    }
    
    override func nukeAllSubmissionCommentNotifications() async -> NotificationPreviews {
        notificationPreviews
    }
    
    override func nukeAllJournalNotifications() async -> NotificationPreviews {
        notificationPreviews
    }
    
    override func avatarUrl(for user: String) async -> URL? {
        nil
    }
}

extension OfflineFASession {
    static let `default` = OfflineFASession(sampleUsername: "DemoUser", submissions: [
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
    ], notifications: ([
            .init(cid: 172177443, author: "furrycount", displayAuthor: "Furrycount", submissionTitle: "FurAffinity iOS App 1.3 Update",
                  datetime: "on Apr 30, 2023 09:50 PM", naturalDatetime: "a few seconds ago",
                  submissionUrl: URL(string: "https://www.furaffinity.net/view/49215481/#cid:172177443")!),
            .init(cid: 172177425, author: "furrycount", displayAuthor: "Furrycount", submissionTitle: "FurAffinity iOS App 1.3 Update",
                  datetime: "on Apr 30, 2023 09:49 PM", naturalDatetime: "a minute ago",
                  submissionUrl: URL(string: "https://www.furaffinity.net/view/49215481/#cid:172177425")!)
        ], [
            .init(id: 10526001, author: "holt-odium", displayAuthor: "Holt-Odium", title: "📝 3 Slots are available",
              datetime: "on Apr 14, 2023 08:23 PM", naturalDatetime: "18 hours ago",
              journalUrl: URL(string: "https://www.furaffinity.net/journal/10526001/")!),
            .init(id: 10521084, author: "holt-odium", displayAuthor: "Holt-Odium", title: "Sketch commission are open (115$)",
              datetime: "on Apr 8, 2023 07:00 PM", naturalDatetime: "a week ago",
              journalUrl: URL(string: "https://www.furaffinity.net/journal/10521084/")!),
            .init(id: 10516170, author: "rudragon", displayAuthor: "RUdragon", title: "UPGRADES ARE OPEN!!! 5",
              datetime: "on Apr 2, 2023 11:59 PM", naturalDatetime: "12 days ago",
              journalUrl: URL(string: "https://www.furaffinity.net/journal/10516170/")!),
            .init(id: 10512063, author: "ishiru", displayAuthor: "Ishiru", title: "30 minutes before end of auction",
              datetime: "on Mar 29, 2023 03:33 PM", naturalDatetime: "17 days ago",
              journalUrl: URL(string: "https://www.furaffinity.net/journal/10512063/")!),
            .init(id: 10511753, author: "ishiru", displayAuthor: "Ishiru", title: "one day left",
              datetime: "on Mar 29, 2023 07:42 AM", naturalDatetime: "17 days ago",
              journalUrl: URL(string: "https://www.furaffinity.net/journal/10511753/")!)
        ])
    )
    
    static let empty = OfflineFASession(sampleUsername: "Demo User", submissions: [], notes: [], notifications: ([], []))
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

extension FAComment {
    private static let terrinissAvatarUrl = URL(string: "https://a.furaffinity.net/1616615925/terriniss.gif")!
    static let demo: [FAComment] = [
        .init(cid: 166652793, author: "terriniss", displayAuthor: "Terriniss", authorAvatarUrl: terrinissAvatarUrl, datetime: "Aug 11, 2022 09:48 PM", naturalDatetime: "2 months ago",
              htmlMessage: "BID HERE \n<br> Moon".selfContainedFAHtmlComment, answers: [
                .init(cid: 166653891, author: "terriniss", displayAuthor: "Terriniss", authorAvatarUrl: terrinissAvatarUrl, datetime: "Aug 11, 2022 10:58 PM", naturalDatetime: "2 months ago",
                      htmlMessage: "SakuraSlowly (DA) - SB".selfContainedFAHtmlComment, answers: [
                        .init(cid: 166658565, author: "terriniss", displayAuthor: "Terriniss", authorAvatarUrl: terrinissAvatarUrl, datetime: "Aug 12, 2022 05:16 AM", naturalDatetime: "2 months ago",
                              htmlMessage: "DeathPanda21 (da) - 55$".selfContainedFAHtmlComment, answers: [])
                      ])
              ]),
        .init(cid: 166653340, author: "rurudaspippen", displayAuthor: "RuruDasPippen", authorAvatarUrl: URL(string: "https://a.furaffinity.net/1643948243/rurudaspippen.gif")!,
              datetime: "Aug 11, 2022 10:23 PM", naturalDatetime: "2 months ago", htmlMessage: "Look at the babies!".selfContainedFAHtmlComment, answers: [])
    ]
}

extension FASubmission {
    static let demo: FASubmission = {
        let htmlDescription = "YCH for \n<a href=\"/user/mikazukihellfire\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20211017/mikazukihellfire.gif\" align=\"middle\" title=\"MikazukiHellfire\" alt=\"MikazukiHellfire\">&nbsp;MikazukiHellfire</a>\n<br> \n<br> Medea © \n<a href=\"/user/mikazukihellfire\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20211017/mikazukihellfire.gif\" align=\"middle\" title=\"MikazukiHellfire\" alt=\"MikazukiHellfire\">&nbsp;MikazukiHellfire</a>\n<br> \n<br> \n<br> \n<br> \n<br> *******************************\n<br> * \n<a class=\"auto_link named_url\" href=\"http://ko-fi.com/J3J16KSH\">Feed me with coffee?</a>\n<br> * \n<a class=\"auto_link named_url\" href=\"https://www.furaffinity.net/gallery/annetpeas/\">My Gallery</a>\n<br> * \n<a class=\"auto_link named_url\" href=\"https://twitter.com/AnnetPeas_Art\">Twitter</a>"
        
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
            comments: FAComment.demo)
    }()
}

extension FAJournal {
    static let demo: FAJournal = {
        let htmlDescription = """
what you will need to get one.\n<br> - if you got a sketch you can get an upgrade.\n<br> -comment on this Journal to get in line(ill work down the line and work in that order)\n<br> -make sure you have the funds to get a spot.\n<br> -if you have one more then one sketch you can have 3 at the most i can upgrade ( make sure you have the funds if your doing more then one)\n<br> -ill note you to get the ref and info to upgrade your pic. the farther your in line the longer will take to get to you, so PLZ try put aside the funds till i get to you in line.\n<br> -you will be paying $75 or more depending on what you want done.\n<br> for just you OC and no BG will $75 per OC.\n<br> BG and or extra stuff added will be $100 more or less.\n<br> \n<br> after this will go back to sketches then back to upgrades.\n<br> \n<br> depending on how much the person asks could take me more or less time to get to the next one in line.\n<br> so PLZ wait for not to get your info.\n<br> \n<br> GOOD LUCK TO EVERYONE.\n<br> \n<br> \n<br> 1. \n<a href=\"/user/fukothenimbat\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20230416/fukothenimbat.gif\" align=\"middle\" title=\"fukothenimbat\" alt=\"fukothenimbat\">&nbsp;fukothenimbat</a>\n<br> \n<br> 2. \n<a href=\"/user/zacharywulf\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20230416/zacharywulf.gif\" align=\"middle\" title=\"zacharywulf\" alt=\"zacharywulf\">&nbsp;zacharywulf</a>\n<br> \n<br> 3. \n<a href=\"/user/leacrea\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20230416/leacrea.gif\" align=\"middle\" title=\"leacrea\" alt=\"leacrea\">&nbsp;leacrea</a>\n<br> \n<br> 4. \n<a href=\"/user/thegrapedemon\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20230416/thegrapedemon.gif\" align=\"middle\" title=\"thegrapedemon\" alt=\"thegrapedemon\">&nbsp;thegrapedemon</a>\n<br> \n<br> 5. \n<a href=\"/user/shadoweddraco\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20230416/shadoweddraco.gif\" align=\"middle\" title=\"shadoweddraco\" alt=\"shadoweddraco\">&nbsp;shadoweddraco</a>\n<br> \n<br> for not this will be the last one then going back to sketches then maybe open one more then back to one more upgrade but will see how things go.
"""
        
        return FAJournal(
            url: URL(string: "https://www.furaffinity.net/journal/10516170/")!,
            author: "rudragon",
            displayAuthor: "RUdragon",
            authorAvatarUrl: URL(string: "https://a.furaffinity.net/1424255659/rudragon.gif")!,
            title: "UPGRADES ARE OPEN!!! 5",
            datetime: "Apr 2, 2023 11:59 PM",
            naturalDatetime: "2 weeks ago",
            htmlDescription: htmlDescription,
            comments: FAComment.demo)
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

extension FAUser {
    private static let htmlDescription = """
<code class=\"bbcode bbcode_center\"> <a href=\"/user/vampireknightlampleftplz\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/vampireknightlampleftplz.gif\" align=\"middle\" title=\"vampireknightlampleftplz\" alt=\"vampireknightlampleftplz\"></a> <a href=\"/user/hawthornbloodmoon\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/hawthornbloodmoon.gif\" align=\"middle\" title=\"hawthornbloodmoon\" alt=\"hawthornbloodmoon\"></a> <a href=\"/user/vampireknightlamprightplz\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/vampireknightlamprightplz.gif\" align=\"middle\" title=\"vampireknightlamprightplz\" alt=\"vampireknightlamprightplz\"></a> <br> <br> <h4 class=\"bbcode bbcode_h4\"> ∼ 👣 𝙃𝙖𝙫𝙚 𝙖 𝙣𝙞𝙘𝙚 𝙙𝙖𝙮, 𝙩𝙧𝙖𝙫𝙚𝙡𝙚𝙧 <br> 𝘾𝙤𝙢𝙚 𝙘𝙡𝙤𝙨𝙚𝙧 𝙖𝙣𝙙 𝙄\'𝙡𝙡 𝙨𝙝𝙤𝙬 𝙮𝙤𝙪 𝙞𝙣𝙘𝙧𝙚𝙙𝙞𝙗𝙡𝙚 𝙗𝙚𝙖𝙨𝙩𝙨 🐾 ∼ </h4><br> \n <hr class=\"bbcode bbcode_hr\"> <br> My name is <strong class=\"bbcode bbcode_b\">Terriniss.</strong> <br> Briefly - <strong class=\"bbcode bbcode_b\">Tira.</strong> <br> <br> <span class=\"bbcode\" style=\"color: #C92A2A;\">▸▹</span> 26 y.o. <span class=\"bbcode\" style=\"color: #000000;\">●</span> RU/ENG <span class=\"bbcode\" style=\"color: #000000;\">●</span> SFW <span class=\"bbcode\" style=\"color: #000000;\">●</span> Digital artist <span class=\"bbcode\" style=\"color: #C92A2A;\">◂◃</span><br> <span class=\"bbcode\" style=\"color: #C92A2A;\">▸▹</span> I\'m glad to see you here! <span class=\"bbcode\" style=\"color: #C92A2A;\">◂◃</span><br> <br> <sub class=\"bbcode bbcode_sub\"> 🌑 My main job here is creating fantasy creatures.<br> Mystical and dark themes are my favorite, but sometimes, on the contrary, I want to create something light.<br> I\'m trying to make the creature as alive as possible emotionally, <br> I want you to see his emotions when you look into his face, <br> or at the expressions of his body. And so that when I looked into his face, I could see them too.<br> I\'m glad when I can do it. And I\'m glad if you notice it. 🌕</sub> <br> <br> <span class=\"bbcode\" style=\"color: #C92A2A;\">☘</span> Thank you for your attention to my work. This is really important to me! <span class=\"bbcode\" style=\"color: #C92A2A;\">☘</span><br> <br> \n <hr class=\"bbcode bbcode_hr\"> <br> <u class=\"bbcode bbcode_u\"> My second account, for YCHes </u> <br> <a href=\"/user/terriniss-yches\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/terriniss-yches.gif\" align=\"middle\" title=\"terriniss-yches\" alt=\"terriniss-yches\"></a><br> <br> <u class=\"bbcode bbcode_u\"> My dear friends </u> <br> <a href=\"/user/obsidianna\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/obsidianna.gif\" align=\"middle\" title=\"obsidianna\" alt=\"obsidianna\"></a> <a href=\"/user/jackdeath11\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/jackdeath11.gif\" align=\"middle\" title=\"jackdeath11\" alt=\"jackdeath11\"></a> <a href=\"/user/draynd\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/draynd.gif\" align=\"middle\" title=\"draynd\" alt=\"draynd\"></a> <a href=\"/user/sapfirachib\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/sapfirachib.gif\" align=\"middle\" title=\"sapfirachib\" alt=\"sapfirachib\"></a> <a href=\"/user/noxor\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/noxor.gif\" align=\"middle\" title=\"noxor\" alt=\"noxor\"></a> <a href=\"/user/vetka\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/vetka.gif\" align=\"middle\" title=\"vetka\" alt=\"vetka\"></a> <a href=\"/user/rurudaspippen\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/rurudaspippen.gif\" align=\"middle\" title=\"rurudaspippen\" alt=\"rurudaspippen\"></a> <a href=\"/user/innart\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/innart.gif\" align=\"middle\" title=\"innart\" alt=\"innart\"></a> <a href=\"/user/chefraven\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20221128/chefraven.gif\" align=\"middle\" title=\"chefraven\" alt=\"chefraven\"></a><br> <sub class=\"bbcode bbcode_sub\"> (Sorry if I forgot to mention anyone here)</sub> <br> <br> \n <hr class=\"bbcode bbcode_hr\"> <br> <span class=\"bbcode\" style=\"color: #000000;\">🕷</span> <u class=\"bbcode bbcode_u\"><span class=\"bbcode\" style=\"color: #EB3131;\"><strong class=\"bbcode bbcode_b\">Art-status</strong></span></u> <span class=\"bbcode\" style=\"color: #000000;\">🕷</span> <br> <span class=\"bbcode\" style=\"color: #000000;\">╭</span><span class=\"bbcode\" style=\"color: #131313;\">━</span><span class=\"bbcode\" style=\"color: #262626;\">━</span><span class=\"bbcode\" style=\"color: #393939;\">━</span><span class=\"bbcode\" style=\"color: #4C4C4C;\">━</span><span class=\"bbcode\" style=\"color: #606060;\">━</span><span class=\"bbcode\" style=\"color: #737373;\">━</span><span class=\"bbcode\" style=\"color: #868686;\">━</span><span class=\"bbcode\" style=\"color: #999999;\">━</span><span class=\"bbcode\" style=\"color: #ADADAD;\">━</span><span class=\"bbcode\" style=\"color: #999A99;\">━</span><span class=\"bbcode\" style=\"color: #868786;\">━</span><span class=\"bbcode\" style=\"color: #737473;\">━</span><span class=\"bbcode\" style=\"color: #606160;\">━</span><span class=\"bbcode\" style=\"color: #4C4E4C;\">━</span><span class=\"bbcode\" style=\"color: #393B39;\">━</span><span class=\"bbcode\" style=\"color: #262826;\">━</span><span class=\"bbcode\" style=\"color: #131513;\">━</span><span class=\"bbcode\" style=\"color: #000300;\">╮</span><br> <strong class=\"bbcode bbcode_b\">Commissions</strong> - open:<br> - headshot (w/o detailed bg)<br> - Haflbody (w/o detailed bg)<br> - custom design.<br> <br> <strong class=\"bbcode bbcode_b\">Collabs</strong> - maybe<br> <br> <strong class=\"bbcode bbcode_b\">Requests</strong> - no :&lt;<br> <span class=\"bbcode\" style=\"color: #000000;\">╰</span><span class=\"bbcode\" style=\"color: #131313;\">━</span><span class=\"bbcode\" style=\"color: #262626;\">━</span><span class=\"bbcode\" style=\"color: #393939;\">━</span><span class=\"bbcode\" style=\"color: #4C4C4C;\">━</span><span class=\"bbcode\" style=\"color: #606060;\">━</span><span class=\"bbcode\" style=\"color: #737373;\">━</span><span class=\"bbcode\" style=\"color: #868686;\">━</span><span class=\"bbcode\" style=\"color: #999999;\">━</span><span class=\"bbcode\" style=\"color: #ADADAD;\">━</span><span class=\"bbcode\" style=\"color: #999A99;\">━</span><span class=\"bbcode\" style=\"color: #868786;\">━</span><span class=\"bbcode\" style=\"color: #737473;\">━</span><span class=\"bbcode\" style=\"color: #606160;\">━</span><span class=\"bbcode\" style=\"color: #4C4E4C;\">━</span><span class=\"bbcode\" style=\"color: #393B39;\">━</span><span class=\"bbcode\" style=\"color: #262826;\">━</span><span class=\"bbcode\" style=\"color: #131513;\">━</span><span class=\"bbcode\" style=\"color: #000300;\">╯</span><br> <br> <a class=\"auto_link named_url\" href=\"https://www.deviantart.com/terriniss/\">DeviantArt</a> <br> <br> <h5 class=\"bbcode bbcode_h5\"><span class=\"bbcode\" style=\"color: #C92A2A;\">🕷</span> <a class=\"auto_link named_url\" href=\"https://www.patreon.com/Terriniss/id0\">PATREON</a> <span class=\"bbcode\" style=\"color: #C92A2A;\">🕷</span><br> <span class=\"bbcode\" style=\"color: #C92A2A;\">🕷</span> (Here you can see sketches and works that will NOT be uploaded to other galleries!) <span class=\"bbcode\" style=\"color: #C92A2A;\">🕷</span></h5> <br> <br> <sub class=\"bbcode bbcode_sub\"> P.S. Unfortunately, English is not my native language. I often have to communicate through a translator. Nevertheless, I will be glad to talk to any of you!</sub> </code>
""".selfContainedFAHtmlSubmission
    
    static let demo = FAUser(
        userName: "demo",
        displayName: "Demo",
        avatarUrl: URL(string: "https://a.furaffinity.net/20230319/furrycount.gif")!,
        bannerUrl: URL(string: "https://www.furaffinity.net/themes/beta/img/banners/logo/fa-banner-winter.jpg")!,
        htmlDescription: htmlDescription
    )
}
