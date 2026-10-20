import Testing
import Foundation
import FAPages
@testable import FAKit

/// A list that shifts between two page loads repeats an item across the page boundary,
/// and a repeated id crashes a Compose `List`.
struct PagedListAppendingTests {
    private func preview(_ sid: Int) -> FASubmissionPreview {
        let url = URL(string: "https://www.furaffinity.net/view/\(sid)/")!
        return .init(sid: sid, url: url, thumbnailUrl: url, thumbnailWidthOnHeightRatio: 1,
                     title: "\(sid)", author: "a", displayAuthor: "A", rating: .general)
    }

    private func gallery(_ sids: [Int]) -> FAUserGalleryLike {
        .init(url: URL(string: "https://www.furaffinity.net/gallery/a/")!, displayAuthor: "A",
              previews: sids.map(preview), nextPageUrl: nil, folderGroups: [])
    }

    private func watchlist(_ names: [String]) -> FAWatchlist {
        .init(currentUser: .init(name: "a", displayName: "A"), watchDirection: .watching,
              users: names.map { .init(name: $0, displayName: $0) }, nextPageUrl: nil)
    }

    @Test
    func galleryAppendingDropsRepeatedSubmissions() {
        let appended = gallery([3, 2]).appending(gallery([2, 1]))
        #expect(appended.previews.map(\.sid) == [3, 2, 1])
    }

    @Test
    func watchlistAppendingDropsRepeatedUsers() {
        let appended = watchlist(["b", "c"]).appending(watchlist(["c", "d"]))
        #expect(appended.users.map(\.name) == ["b", "c", "d"])
    }
}
