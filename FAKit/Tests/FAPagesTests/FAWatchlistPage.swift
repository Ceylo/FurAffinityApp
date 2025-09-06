//
//  FAWatchlistPage.swift
//  FAKit
//
//  Created by Ceylo on 02/09/2024.
//

import XCTest
@testable import FAPages

final class FAWatchlistPageTests: XCTestCase {
    func testSinglePageWatchlist_returnsUsers() async throws {
        let data = testData("www.furaffinity.net:watchlist:by:terriniss.html")
        let pageOpt = await FAWatchlistPage(
            data: data,
            baseUri: URL(string: "https://www.furaffinity.net/watchlist/by/terriniss/")!
        )
        let page = try XCTUnwrap(pageOpt)
        
        let expected = FAWatchlistPage(
            currentUser: .init(name: "terriniss", displayName: "Terriniss"),
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
                .init(name: "amirumm", displayName: "AmiRumm"),
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
                .init(name: "dablazor", displayName: "Da_Blazor"),
                .init(name: "dalekfell", displayName: "DalekFell"),
                .init(name: "darkgem", displayName: "darkgem"),
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
                .init(name: "forgeddarkness", displayName: "ForgedDarkness"),
                .init(name: "foxyfembo1", displayName: "FoxyFemBo1"),
                .init(name: "free-opium", displayName: "Free-Opium"),
                .init(name: "henjikotetsu", displayName: "HenjiKotetsu"),
                .init(name: "slumphy", displayName: "Hermux"),
                .init(name: "honovy", displayName: "Honovy"),
                .init(name: "hontoriel", displayName: "Hontoriel"),
                .init(name: "hun", displayName: "Hun"),
                .init(name: "innart", displayName: "inn_art"),
                .init(name: "jackdeath11", displayName: "JackDeath11"),
                .init(name: "jackthewerewolf", displayName: "JacktheWerewolf"),
                .init(name: "juliathedragoncat", displayName: "JuliaTheDragonCat"),
                .init(name: "jyirilazybones", displayName: "JyiriLazybones"),
                .init(name: "kageichi", displayName: "Kageichi"),
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
                .init(name: "flutesong", displayName: "Natani Flutesong"),
                .init(name: "nomax", displayName: "Nomax"),
                .init(name: "novaskitten", displayName: "NovaSkitten"),
                .init(name: "noxor", displayName: "Noxor"),
                .init(name: "obsidianna", displayName: "Obsidianna"),
                .init(name: "osariaallyeid", displayName: "OsariaAllyeid"),
                .init(name: "ottobergen", displayName: "ottobergen"),
                .init(name: "ottomonpyre", displayName: "OttoMonpyre"),
                .init(name: "pacelic", displayName: "Pacelic"),
                .init(name: "pawbz", displayName: "Pawbz"),
                .init(name: "kaji", displayName: "Pazu"),
                .init(name: "pervysensei", displayName: "PervySensei"),
                .init(name: "pshe", displayName: "Pshe"),
                .init(name: "queenofcroia", displayName: "QueenOfCroia"),
                .init(name: "racoonwolf", displayName: "racoonwolf"),
                .init(name: "raharu95", displayName: "Raharu95"),
                .init(name: "immaturecontent", displayName: "Razz Redcrest"),
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
                .init(name: "smileeeeeee", displayName: "SMU"),
                .init(name: "soongdae", displayName: "SoongDae"),
                .init(name: "stigmata", displayName: "Stigmata"),
                .init(name: "stretchsnake", displayName: "Stretchsnake"),
                .init(name: "nordwolfe", displayName: "SugarFolf"),
                .init(name: "tacklebox", displayName: "tacklebox"),
                .init(name: "teckelarts", displayName: "Teckelarts"),
                .init(name: "terrygrimm", displayName: "Terry_Grimm"),
                .init(name: "thanshuhai", displayName: "thanshuhai"),
                .init(name: "the-witness", displayName: "The-Witness"),
                .init(name: "darktiggy", displayName: "Tigz Hunter"),
                .init(name: "tjtiger", displayName: "Tj_Tiger"),
                .init(name: "ursa.h", displayName: "Ursa.H"),
                .init(name: "victoranne", displayName: "Victor_Anne"),
                .init(name: "viiburnum", displayName: "Viiburnum"),
                .init(name: "vincentlim", displayName: "VincentLim"),
                .init(name: "poprocker566", displayName: "Vinfang"),
                .init(name: "vinrage", displayName: "VinRage"),
                .init(name: "weare...sexybears...", displayName: "We_are...Sexy_bearS..."),
                .init(name: "whitemantis", displayName: "WhiteMantis"),
                .init(name: "wolf12345", displayName: "wolf12345"),
                .init(name: "xepxyu", displayName: "xepxyu"),
                .init(name: "xerxis", displayName: "Xerxis"),
                .init(name: "zemus98", displayName: "Zemus98"),
                .init(name: "zullkharn", displayName: "ZullKharn"),
                .init(name: "~inkyenigma~", displayName: "~InkyEnigma~"),
                .init(name: "~rizonik~", displayName: "~RIZONIK~"),
            ],
            nextPageUrl: nil
        )
        
        XCTAssertEqual(page, expected)
    }
    
    func testMultiPageWatchlist_returnsUsersAndPage() async throws {
        let data = testData("www.furaffinity.net:watchlist:to:terriniss.html")
        let pageOpt = await FAWatchlistPage(
            data: data,
            baseUri: URL(string: "https://www.furaffinity.net/watchlist/to/terriniss/")!
        )
        let page = try XCTUnwrap(pageOpt)
        XCTAssertEqual(page.users.count, 200)
        XCTAssertEqual(
            page.nextPageUrl,
            URL(string: "https://www.furaffinity.net/watchlist/to/terriniss?page=2")
        )
    }
}
