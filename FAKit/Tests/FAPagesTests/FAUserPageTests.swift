//
//  FAUserPageTests.swift
//  
//
//  Created by Ceylo on 05/12/2021.
//

import XCTest
@testable import FAPages

class FAUserPageTests: XCTestCase {
    func testUserPage_isParsed() async throws {
        let url = URL(string: "https://www.furaffinity.net/user/terriniss")!
        let data = testData("www.furaffinity.net:user:terriniss.html")
        let page = await FAUserPage(data: data, url: url)
        XCTAssertNotNil(page)
        
        let htmlDescription = """
<code class="bbcode bbcode_center"> <a href="/user/vampireknightlampleftplz" class="iconusername"><img src="//a.furaffinity.net/20250304/vampireknightlampleftplz.gif" align="middle" title="vampireknightlampleftplz" alt="vampireknightlampleftplz" /></a> <a href="/user/hawthornbloodmoon" class="iconusername"><img src="//a.furaffinity.net/20250304/hawthornbloodmoon.gif" align="middle" title="hawthornbloodmoon" alt="hawthornbloodmoon" /></a> <a href="/user/vampireknightlamprightplz" class="iconusername"><img src="//a.furaffinity.net/20250304/vampireknightlamprightplz.gif" align="middle" title="vampireknightlamprightplz" alt="vampireknightlamprightplz" /></a> <br /> <br /> <h4 class="bbcode bbcode_h4"> ∼ 👣 𝙃𝙖𝙫𝙚 𝙖 𝙣𝙞𝙘𝙚 𝙙𝙖𝙮, 𝙩𝙧𝙖𝙫𝙚𝙡𝙚𝙧 <br /> 𝘾𝙤𝙢𝙚 𝙘𝙡𝙤𝙨𝙚𝙧 𝙖𝙣𝙙 𝙄\'𝙡𝙡 𝙨𝙝𝙤𝙬 𝙮𝙤𝙪 𝙞𝙣𝙘𝙧𝙚𝙙𝙞𝙗𝙡𝙚 𝙗𝙚𝙖𝙨𝙩𝙨 🐾 ∼ </h4><br /> \n <hr class="bbcode bbcode_hr" /> <br /> My name is <strong class="bbcode bbcode_b">Terriniss.</strong> <br /> Briefly - <strong class="bbcode bbcode_b">Tira.</strong> <br /> <br /> <span class="bbcode" style="color: #C92A2A;">▸▹</span> 28 y.o. <span class="bbcode" style="color: #000000;">●</span> RU/ENG <span class="bbcode" style="color: #000000;">●</span> SFW <span class="bbcode" style="color: #000000;">●</span> Digital artist <span class="bbcode" style="color: #C92A2A;">◂◃</span><br /> <span class="bbcode" style="color: #C92A2A;">▸▹</span> I\'m glad to see you here! <span class="bbcode" style="color: #C92A2A;">◂◃</span><br /> <br /> <sub class="bbcode bbcode_sub"> 🌑 My main job here is creating fantasy creatures.<br /> Mystical and dark themes are my favorite, but sometimes, on the contrary, I want to create something light.<br /> I\'m trying to make the creature as alive as possible emotionally, <br /> I want you to see his emotions when you look into his face, <br /> or at the expressions of his body. And so that when I looked into his face, I could see them too.<br /> I\'m glad when I can do it. And I\'m glad if you notice it. 🌕</sub> <br /> <br /> <span class="bbcode" style="color: #C92A2A;">☘</span> Thank you for your attention to my work. This is really important to me! <span class="bbcode" style="color: #C92A2A;">☘</span><br /> <br /> \n <hr class="bbcode bbcode_hr" /> <br /> <u class="bbcode bbcode_u"> My second account, for YCHes </u> <br /> <a href="/user/terriniss-yches" class="iconusername"><img src="//a.furaffinity.net/20250304/terriniss-yches.gif" align="middle" title="terriniss-yches" alt="terriniss-yches" /></a><br /> <br /> <u class="bbcode bbcode_u"> My dear friends </u> <br /> <a href="/user/obsidianna" class="iconusername"><img src="//a.furaffinity.net/20250304/obsidianna.gif" align="middle" title="obsidianna" alt="obsidianna" /></a> <a href="/user/jackdeath11" class="iconusername"><img src="//a.furaffinity.net/20250304/jackdeath11.gif" align="middle" title="jackdeath11" alt="jackdeath11" /></a> <a href="/user/draynd" class="iconusername"><img src="//a.furaffinity.net/20250304/draynd.gif" align="middle" title="draynd" alt="draynd" /></a> <a href="/user/sapfirachib" class="iconusername"><img src="//a.furaffinity.net/20250304/sapfirachib.gif" align="middle" title="sapfirachib" alt="sapfirachib" /></a> <a href="/user/noxor" class="iconusername"><img src="//a.furaffinity.net/20250304/noxor.gif" align="middle" title="noxor" alt="noxor" /></a> <a href="/user/vetka" class="iconusername"><img src="//a.furaffinity.net/20250304/vetka.gif" align="middle" title="vetka" alt="vetka" /></a> <a href="/user/rurudaspippen" class="iconusername"><img src="//a.furaffinity.net/20250304/rurudaspippen.gif" align="middle" title="rurudaspippen" alt="rurudaspippen" /></a> <a href="/user/innart" class="iconusername"><img src="//a.furaffinity.net/20250304/innart.gif" align="middle" title="innart" alt="innart" /></a> <a href="/user/chefraven" class="iconusername"><img src="//a.furaffinity.net/20250304/chefraven.gif" align="middle" title="chefraven" alt="chefraven" /></a><br /> <sub class="bbcode bbcode_sub"> (Sorry if I forgot to mention anyone here)</sub> <br /> <br /> \n <hr class="bbcode bbcode_hr" /> <br /> <span class="bbcode" style="color: #000000;">🕷</span> <u class="bbcode bbcode_u"><span class="bbcode" style="color: #EB3131;"><strong class="bbcode bbcode_b">Art-status</strong></span></u> <span class="bbcode" style="color: #000000;">🕷</span> <br /> <span class="bbcode" style="color: #000000;">╭</span><span class="bbcode" style="color: #131313;">━</span><span class="bbcode" style="color: #262626;">━</span><span class="bbcode" style="color: #393939;">━</span><span class="bbcode" style="color: #4C4C4C;">━</span><span class="bbcode" style="color: #606060;">━</span><span class="bbcode" style="color: #737373;">━</span><span class="bbcode" style="color: #868686;">━</span><span class="bbcode" style="color: #999999;">━</span><span class="bbcode" style="color: #ADADAD;">━</span><span class="bbcode" style="color: #999A99;">━</span><span class="bbcode" style="color: #868786;">━</span><span class="bbcode" style="color: #737473;">━</span><span class="bbcode" style="color: #606160;">━</span><span class="bbcode" style="color: #4C4E4C;">━</span><span class="bbcode" style="color: #393B39;">━</span><span class="bbcode" style="color: #262826;">━</span><span class="bbcode" style="color: #131513;">━</span><span class="bbcode" style="color: #000300;">╮</span><br /> <strong class="bbcode bbcode_b">Commissions</strong> - open<br /> <br /> <strong class="bbcode bbcode_b">Collabs</strong> - maybe<br /> <br /> <strong class="bbcode bbcode_b">Requests</strong> - no :&lt;<br /> <span class="bbcode" style="color: #000000;">╰</span><span class="bbcode" style="color: #131313;">━</span><span class="bbcode" style="color: #262626;">━</span><span class="bbcode" style="color: #393939;">━</span><span class="bbcode" style="color: #4C4C4C;">━</span><span class="bbcode" style="color: #606060;">━</span><span class="bbcode" style="color: #737373;">━</span><span class="bbcode" style="color: #868686;">━</span><span class="bbcode" style="color: #999999;">━</span><span class="bbcode" style="color: #ADADAD;">━</span><span class="bbcode" style="color: #999A99;">━</span><span class="bbcode" style="color: #868786;">━</span><span class="bbcode" style="color: #737473;">━</span><span class="bbcode" style="color: #606160;">━</span><span class="bbcode" style="color: #4C4E4C;">━</span><span class="bbcode" style="color: #393B39;">━</span><span class="bbcode" style="color: #262826;">━</span><span class="bbcode" style="color: #131513;">━</span><span class="bbcode" style="color: #000300;">╯</span><br /> <br /> <a class="auto_link named_url" href="https://www.deviantart.com/terriniss/">DeviantArt</a> <br /> <br /> <h5 class="bbcode bbcode_h5"><span class="bbcode" style="color: #C92A2A;">🕷</span> <a class="auto_link named_url" href="https://www.patreon.com/Terriniss/id0">PATREON</a> <span class="bbcode" style="color: #C92A2A;">🕷</span><br /> <span class="bbcode" style="color: #C92A2A;">🕷</span> (Here you can see sketches and works that will NOT be uploaded to other galleries!) <span class="bbcode" style="color: #C92A2A;">🕷</span></h5> <br /> <br /> <sub class="bbcode bbcode_sub"> P.S. Unfortunately, English is not my native language. I often have to communicate through a translator. Nevertheless, I will be glad to talk to any of you!</sub> </code>
"""
        let shouts: [FAPageComment] = [
            .visible(.init(
                cid: 55999777,
                indentation: 0,
                author: "mengshi",
                displayAuthor: "MengShi",
                datetime: "Dec 6, 2024 10:51 AM",
                naturalDatetime: "3 months ago",
                htmlMessage: "Love your gallery owo"
            )),
            .visible(.init(
                cid: 55784394,
                indentation: 0,
                author: "dumbdogfinn",
                displayAuthor: "DumbDogFinn",
                datetime: "Sep 18, 2024 04:09 AM",
                naturalDatetime: "5 months ago",
                htmlMessage: "thanks for the watch! ur brush work is CRAZY"
            )),
            .visible(.init(
                cid: 55499499,
                indentation: 0,
                author: "tarotxviii",
                displayAuthor: "TarotXVIII",
                datetime: "Jun 7, 2024 09:29 PM",
                naturalDatetime: "9 months ago",
                htmlMessage: "Your line-work is so beautiful -- I absolutely love the thick angular lines."
            )),
            .visible(.init(
                cid: 54925500,
                indentation: 0,
                author: "warrabbit",
                displayAuthor: "WarRabbit",
                datetime: "Nov 25, 2023 02:57 AM",
                naturalDatetime: "a year ago",
                htmlMessage: "God your stuff is gorgeous. Love the style."
            )),
            .visible(.init(
                cid: 54857699,
                indentation: 0,
                author: "nonamepiz",
                displayAuthor: "NoNamepIz",
                datetime: "Nov 2, 2023 07:46 AM",
                naturalDatetime: "a year ago",
                htmlMessage: "Ваши адопты великолепны.. Нет слов, одни эмоции *^*"
            )),
            .visible(.init(
                cid: 54843072,
                indentation: 0,
                author: "shuhannazy",
                displayAuthor: "Shuhannazy",
                datetime: "Oct 28, 2023 12:01 PM",
                naturalDatetime: "a year ago",
                htmlMessage: "Your creativity is wonderful, i've sat here for hours looking at your creations and I dont regret it a bit."
            )),
            .visible(.init(
                cid: 54569442,
                indentation: 0,
                author: "sadisticss",
                displayAuthor: "Sadisticss",
                datetime: "Jul 29, 2023 11:16 PM",
                naturalDatetime: "a year ago",
                htmlMessage: "Hola, dear! U have nice gallery &lt;3"
            )),
            .visible(.init(
                cid: 53766730,
                indentation: 0,
                author: "mostevilpupper",
                displayAuthor: "MostEvilPupper",
                datetime: "Dec 6, 2022 04:46 AM",
                naturalDatetime: "2 years ago",
                htmlMessage: "An absolutely amazing artist"
            )),
            .visible(.init(
                cid: 53552229,
                indentation: 0,
                author: "flutesong",
                displayAuthor: "Flutesong",
                datetime: "Oct 6, 2022 02:56 PM",
                naturalDatetime: "2 years ago",
                htmlMessage: "Thank you for watching!"
            )),
            .visible(.init(
                cid: 53547789,
                indentation: 0,
                author: "chicken-scratch",
                displayAuthor: "Chicken-Scratch",
                datetime: "Oct 5, 2022 07:11 AM",
                naturalDatetime: "2 years ago",
                htmlMessage: "<a href=\"/user/8bitstarsp1\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20250304/8bitstarsp1.gif\" align=\"middle\" title=\"8bitstarsp1\" alt=\"8bitstarsp1\" /></a> Thank you for watching me! Merp! \n<a href=\"/user/8bitstarsp2\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20250304/8bitstarsp2.gif\" align=\"middle\" title=\"8bitstarsp2\" alt=\"8bitstarsp2\" /></a>"
            )),
            .visible(.init(
                cid: 53545450,
                indentation: 0,
                author: "jackthewerewolf",
                displayAuthor: "JacktheWerewolf",
                datetime: "Oct 4, 2022 05:10 PM",
                naturalDatetime: "2 years ago",
                htmlMessage: "Thank you kindly for the watch'"
            )),
            .visible(.init(
                cid: 53545334,
                indentation: 0,
                author: "-mlady-",
                displayAuthor: "-Mlady-",
                datetime: "Oct 4, 2022 04:39 PM",
                naturalDatetime: "2 years ago",
                htmlMessage: "<code class=\"bbcode bbcode_center\"> <a href=\"/user/8bitstars2\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20250304/8bitstars2.gif\" align=\"middle\" title=\"8bitstars2\" alt=\"8bitstars2\" /></a>♡ Thanks you so much for the watch! You have wonderful adopts ♡<a href=\"/user/8bitstars1\" class=\"iconusername\"><img src=\"//a.furaffinity.net/20250304/8bitstars1.gif\" align=\"middle\" title=\"8bitstars1\" alt=\"8bitstars1\" /></a> </code>"
            ))]
        
        let expected = FAUserPage(
            name: "terriniss",
            displayName: "Terriniss",
            bannerUrl: URL(string: "https://www.furaffinity.net/themes/beta/img/banners/logo/fa-banner-winter.jpg")!,
            htmlDescription: htmlDescription,
            shouts: shouts,
            targetShoutId: nil,
            watchData: .init(watchUrl: URL(string: "https://www.furaffinity.net/unwatch/terriniss/?key=2ad6af6e96e7d8734f5d7ca5dc60026fcebf82e4")!)
        )
        XCTAssertEqual(page, expected)
        
        let urlWithAnchor = URL(string: "https://www.furaffinity.net/user/terriniss#shout-53552229")!
        let pageWithShoutAnchor = await FAUserPage(data: data, url: urlWithAnchor)
        
        let expectedWithShout = FAUserPage(
            name: "terriniss",
            displayName: "Terriniss",
            bannerUrl: URL(string: "https://www.furaffinity.net/themes/beta/img/banners/logo/fa-banner-winter.jpg")!,
            htmlDescription: htmlDescription,
            shouts: shouts,
            targetShoutId: 53552229,
            watchData: .init(watchUrl: URL(string: "https://www.furaffinity.net/unwatch/terriniss/?key=2ad6af6e96e7d8734f5d7ca5dc60026fcebf82e4")!)
        )
        XCTAssertEqual(pageWithShoutAnchor, expectedWithShout)
    }
}
