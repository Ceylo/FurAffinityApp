//
//  FASubmissionPageTests.swift
//  
//
//  Created by Ceylo on 17/10/2021.
//

import Testing
import Foundation
@testable import FAPages

extension [FAFolder] {
    func ignoringUUID() -> Self {
        map { $0.ignoringUUID() }
    }
}

extension FASubmissionPage {
    func ignoringUUID() -> Self {
        .init(
            previewImageUrl: previewImageUrl,
            content: content,
            metadata: metadata.ignoringUUID(),
            htmlDescription: htmlDescription,
            isFavorite: isFavorite,
            favoriteUrl: favoriteUrl,
            comments: comments,
            targetCommentId: targetCommentId,
            acceptsNewComments: acceptsNewComments
        )
    }
}

extension FASubmissionPage.Metadata {
    func ignoringUUID() -> Self {
        .init(
            title: title,
            author: author,
            displayAuthor: displayAuthor,
            datetime: datetime,
            naturalDatetime: naturalDatetime,
            viewCount: viewCount,
            commentCount: commentCount,
            favoriteCount: favoriteCount,
            rating: rating,
            category: category,
            theme: theme,
            species: species,
            fileSize: fileSize,
            keywords: keywords,
            folders: folders.ignoringUUID()
        )
    }
}

struct FASubmissionPageTests {
    @Test
    func submissionPageWithoutComment_isParsed() throws {
        let url = URL(string: "https://www.furaffinity.net/view/49338772/")!
        let data = testData("www.furaffinity.net:view:49338772-nocomment.html")
        let page = try FASubmissionPage(data: data, url: url)
        
        let htmlDescription = """
YCH for 
<a href="/user/lil-maj" class="iconusername"><img src="//a.furaffinity.net/1699843690/lil-maj.gif" title="lil-maj" alt="lil-maj" />&nbsp;<span class="c-usernameBlockSimple username-underlined"><span class="c-usernameBlockSimple__displayName" title="lil-maj">LiL-MAJ</span></span></a> 
<br /> 
<br /> Cody © 
<a href="/user/lil-maj" class="iconusername"><img src="//a.furaffinity.net/1699843690/lil-maj.gif" title="lil-maj" alt="lil-maj" />&nbsp;<span class="c-usernameBlockSimple username-underlined"><span class="c-usernameBlockSimple__displayName" title="lil-maj">LiL-MAJ</span></span></a>
<br /> 
<br /> 
<br /> 
<br /> 
<br /> 
<br /> *******************************
<br /> * 
<a class="auto_link external" href="http://ko-fi.com/J3J16KSH">Feed me with coffee?</a>
<br /> * 
<a class="auto_link" href="https://www.furaffinity.net/gallery/annetpeas/">My Gallery</a>
<br /> * 
<a class="auto_link external" href="https://twitter.com/AnnetPeas_Art">Twitter</a>
"""
        let expected = FASubmissionPage(
            previewImageUrl: URL(string: "https://t.furaffinity.net/49338772@600-1665402309.jpg")!,
            content: .image(.init(
                mediaUrl: URL(string: "https://d.furaffinity.net/art/annetpeas/1665402309/1665402309.annetpeas_the_hookah_fa.png")!,
                widthOnHeightRatio: 1217 / 1280,
                resolution: "1217 x 1280"
            )),
            metadata: .init(
                title: "The hookah",
                author: "annetpeas",
                displayAuthor: "AnnetPeas",
                datetime: "October 10, 2022 01:45:09 PM",
                naturalDatetime: "3 years ago",
                viewCount: 810,
                commentCount: 0,
                favoriteCount: 65,
                rating: .general,
                category: "Artwork (Digital)",
                theme: "All",
                species: "Rabbit / Hare",
                fileSize: "1.22 MB",
                keywords: ["lil-maj", "cody", "female", "girl", "rabbit", "cute", "chibi", "annetpeas", "smoke", "smoking", "hookah", "u_annetpeas", "c_artwork_digital", "t_all", "s_rabbit_hare"],
                folders: [.init(
                    title: "My arts - 2022",
                    url: URL(string: "https://www.furaffinity.net/gallery/annetpeas/folder/1069672/2022/")!,
                    isActive: false
                )]
            ),
            htmlDescription: htmlDescription,
            isFavorite: false,
            favoriteUrl: URL(string: "https://www.furaffinity.net/fav/49338772/?key=8456f8bf60d0d0624adaf06213a48486398a2a964d909dc0d08d3301ffc5d1d7")!,
            comments: [],
            targetCommentId: nil,
            acceptsNewComments: true
        )
        
        #expect(page.ignoringUUID() == expected.ignoringUUID())
    }

    @Test
    func storyTextSubmission_isParsed() throws {
        let url = URL(string: "https://www.furaffinity.net/view/65390484/")!
        let data = testData("www.furaffinity.net:view:65390484:story-text.html")
        let page = try FASubmissionPage(data: data, url: url)

        #expect(page.previewImageUrl == URL(string: "https://t.furaffinity.net/65390484@600-1781809267.jpg")!)
        #expect(page.content == .text(.init(
            documentUrl: URL(string: "https://d.furaffinity.net/download/art/botsu1x/stories/1781809267/1781809267.botsu1x_prepared_with_the_fall_out___1_.docx")!,
            renderedPreviewUrl: URL(string: "https://d.furaffinity.net/art/botsu1x/stories/1781809267/1781809267.thumbnail.botsu1x_prepared_with_the_fall_out___1_.docx.jpg")!
        )))
        #expect(page.metadata.category == "Story")
    }

    @Test
    func storyPdfSubmission_isParsed() throws {
        let url = URL(string: "https://www.furaffinity.net/view/65394772/")!
        let data = testData("www.furaffinity.net:view:65394772:story-pdf.html")
        let page = try FASubmissionPage(data: data, url: url)

        #expect(page.content == .text(.init(
            documentUrl: URL(string: "https://d.furaffinity.net/download/art/vixyyfox/stories/1781832277/1781832277.vixyyfox_3000_-redfurythings.pdf")!,
            renderedPreviewUrl: URL(string: "https://d.furaffinity.net/art/vixyyfox/stories/1781832277/1781832277.thumbnail.vixyyfox_3000_-redfurythings.pdf.jpg")!
        )))
    }

    @Test
    func audioSubmission_isParsed() throws {
        let url = URL(string: "https://www.furaffinity.net/view/57658790/")!
        let data = testData("www.furaffinity.net:view:57658790:audio.html")
        let page = try FASubmissionPage(data: data, url: url)

        #expect(page.previewImageUrl == URL(string: "https://t.furaffinity.net/57658790@600-1722994974.jpg")!)
        #expect(page.content == .audio(.init(
            streamUrl: URL(string: "https://d.furaffinity.net/art/baumarius/music/1722994974/1722994974.baumarius_fading_light.mp3")!,
            downloadUrl: URL(string: "https://d.furaffinity.net/download/art/baumarius/music/1722994974/1722994974.baumarius_fading_light.mp3")!,
            coverImageUrl: URL(string: "https://d.furaffinity.net/art/baumarius/music/1722994974/1722994974.thumbnail.baumarius_fading_light.mp3.jpg")!
        )))
        #expect(page.metadata.category == "Music")
    }

    @Test
    func submissionPageWithCommentsDisabled_isParsed() async throws {
        let url = URL(string: "https://www.furaffinity.net/view/52209828/")!
        let data = testData("www.furaffinity.net:view:52209828-disabled-comments.html")
        let page = try FASubmissionPage(data: data, url: url)

        #expect(page.acceptsNewComments == false)
    }

    @Test
    func submissionPageWithHiddenComment_isParsed() throws {
        let url = URL(string: "https://www.furaffinity.net/view/49917619/")!
        let data = testData("www.furaffinity.net:view:49917619-comment-hidden.html")
        let page = try FASubmissionPage(data: data, url: url)
        #expect(page.comments.count == 12)

        for (index, comment) in page.comments.enumerated() {
            switch comment {
            case .hidden:
                #expect(
                    comment ==
                    .hidden(.init(cid: 168829732, indentation: 6, htmlMessage: "Comment hidden by its owner"))
                )
            case .visible:
                #expect(index != 6)
            }
        }
    }

    @Test
    func submissionPageWithComments_isParsed() throws {
        let url = URL(string: "https://www.furaffinity.net/view/48519387/#cid:166652794")!
        let data = testData("www.furaffinity.net:view:48519387-comments.html")
        let page = try FASubmissionPage(data: data, url: url)
        let expected: [FAPageComment] = [
            .visible(.init(cid: 166652793, indentation: 0, author: "terriniss", displayAuthor: "Terriniss",
                           datetime: "August 12, 2022 02:48:38 AM", naturalDatetime: "4 years ago", htmlMessage: "BID HERE \n<br /> Moon")),
            .visible(.init(cid: 166653891, indentation: 3, author: "terriniss", displayAuthor: "Terriniss",
                           datetime: "August 12, 2022 03:58:01 AM", naturalDatetime: "4 years ago", htmlMessage: "SakuraSlowly (DA) - SB")),
            .visible(.init(cid: 166658565, indentation: 6, author: "terriniss", displayAuthor: "Terriniss",
                           datetime: "August 12, 2022 10:16:32 AM", naturalDatetime: "4 years ago", htmlMessage: "DeathPanda21 (da) - 55$")),
            .visible(.init(cid: 166663244, indentation: 9, author: "terriniss", displayAuthor: "Terriniss",
                           datetime: "August 12, 2022 05:33:53 PM", naturalDatetime: "4 years ago", htmlMessage: "ionightarts (DA) - 60")),
            .visible(.init(cid: 166652794, indentation: 0, author: "terriniss", displayAuthor: "Terriniss",
                           datetime: "August 12, 2022 02:48:44 AM", naturalDatetime: "4 years ago", htmlMessage: "BID HERE \n<br /> Dawn")),
            .visible(.init(cid: 166656182, indentation: 3, author: "terriniss", displayAuthor: "Terriniss",
                           datetime: "August 12, 2022 06:48:34 AM", naturalDatetime: "4 years ago", htmlMessage: "Miss-You-Love (da) - SB")),
            .visible(.init(cid: 166658577, indentation: 6, author: "terriniss", displayAuthor: "Terriniss",
                           datetime: "August 12, 2022 10:17:53 AM", naturalDatetime: "4 years ago", htmlMessage: "LilNikkiBun (da) - 55$")),
            .visible(.init(cid: 166653340, indentation: 0, author: "rurudaspippen", displayAuthor: "RuruDasPippen",
                           datetime: "August 12, 2022 03:23:07 AM", naturalDatetime: "4 years ago", htmlMessage: "Look at the babies!")),
            .visible(.init(cid: 166656573, indentation: 0, author: "fallen5592", displayAuthor: "fallen5592",
                           datetime: "August 12, 2022 07:17:46 AM", naturalDatetime: "4 years ago", htmlMessage: "ooo... more intrestin, cute lil fellas ;p")),
            .visible(.init(cid: 166657876, indentation: 0, author: "alvienta", displayAuthor: "alvienta",
                           datetime: "August 12, 2022 09:08:06 AM", naturalDatetime: "4 years ago", htmlMessage: "these are gorgeous"))
        ]
        
        #expect(expected == page.comments)
        #expect(page.targetCommentId == 166652794)
    }
}
