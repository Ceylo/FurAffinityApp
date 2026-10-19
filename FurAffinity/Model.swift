//
//  Model.swift
//  FurAffinity
//
//  Created by Ceylo on 21/11/2021.
//

import SwiftUI
import FAKit
import Defaults
import OrderedCollections

enum ModelError: LocalizedError {
    case disconnected
    
    var errorDescription: String? {
        switch self {
        case .disconnected:
            return "User is logged out."
        }
    }
}

@MainActor
@Observable
class Model: NotificationsNuker, NotificationsDeleter {
    static private let autorefreshDelay: TimeInterval = 15 * 60
    
    private(set) var session: (any FASession)?
    
    /// `nil` until a fetch actually happened.
    /// After a fetch it contains all found submissions, or an empty array if none was found.
    private(set) var submissionPreviews: OrderedSet<FASubmissionPreview>?
    @ObservationIgnored private(set) var submissionDeletion: StagedDeletion<FASubmissionPreview>!
    private(set) var lastSubmissionPreviewsFetchDate: Date?
    /// Set once after a cold-launch restore from a persisted scroll position, to
    /// ask SubmissionsFeedView to run a scroll-preserving newer-submissions check.
    var shouldCheckForNewerSubmissionsAfterRestore = false

    // MARK: - Exploration (search)
    /// `nil` until a search actually happened. Kept apart from the watched-feed
    /// state so the two Submissions-tab modes never interfere.
    private(set) var searchResults: OrderedSet<FASubmissionPreview>?
    /// Current search criteria, seeded from the persisted value on launch and
    /// written back when the user runs a new search (filters are remembered).
    private(set) var searchQuery: FASearchQuery = Defaults[.lastSearchQuery]
    /// `true` while the last fetched page came back full, so more may exist.
    private(set) var searchCanLoadMore = false
    /// `true` while a search/page fetch is in flight.
    private(set) var isLoadingSearch = false
    /// `true` when the most recent fetch failed while there was nothing to show,
    /// so the UI can offer a retry instead of an endless spinner.
    private(set) var searchLoadFailed = false
    /// Ratings the account may search. Optimistically all ratings until a loaded
    /// page reveals FA restricts some (then the disallowed filter toggles grey out).
    private(set) var searchAllowedRatings: Set<Rating> = Set(Rating.allCases)
    /// `true` when the last search had no keyword and FA returned recent uploads
    /// instead — surfaced in the UI so results aren't mistaken for a keyword search.
    private(set) var searchShowingRecentUploads = false
    
    /// `nil` until a fetch actually happened.
    /// After a fetch it contains all found notes, or an empty array if none was found.
    private(set) var notePreviews: [NotesBox: [FANotePreview]] = [:]
    var unreadInboxNoteCount: Int {
        notePreviews[.inbox]?.filter { $0.unread }.count ?? 0
    }
    private(set) var displayedUnreadNoteCount: Int = 0
    private(set) var lastInboxNotePreviewsFetchDate: Date?
    
    /// nil until a fetch actually happened
    /// After a fetch it contains all found notifications, or an empty array if none was found
    private(set) var notificationPreviews: FANotificationPreviews?
    private(set) var lastNotificationPreviewsFetchDate: Date?
    private(set) var displayedNotificationCount = 0
    @ObservationIgnored private(set) var notificationDeletion: StagedDeletion<StagedNotification>!
    
    private(set) var appInfo = AppInformation()
    private var lastAppInfoUpdate: Date?
    
    /// This store any error encountered in the app, be it from model or views logic.
    /// This is then displayed to the user in a unified way, through ErrorDisplay.
    var errorStorage = ErrorStorage()
    
    @ObservationIgnored private var observationTasks: [Task<Void, Never>] = []
    /// Last logged UserDefaults snapshot, so state-update logs show only the diff.
    @ObservationIgnored private var lastLoggedDefaults: [String: Any] = [:]
    init() {
        submissionDeletion = StagedDeletion(
            send: { [weak self] previews in
                try await self?.getSession().deleteSubmissionPreviews(previews)
            },
            restore: { [weak self] previews in
                self?.reinsertSubmissionPreviews(previews)
            }
        )
        notificationDeletion = StagedDeletion(
            send: { [weak self] items in
                try await self?.sendNotificationsDeletion(items)
            },
            restore: { [weak self] items in
                self?.restoreNotifications(items)
            }
        )
        lastLoggedDefaults = DefaultsChangeLog.snapshot()
        // Defaults yields from whichever thread mutates a key (KVO is synchronous, e.g.
        // background refresh writing latestNotificationIDs off the main actor), but these
        // loop bodies run in the enclosing @MainActor context, so the hop is structural.
        // See defaultsWriteFromBackground… test.
        observationTasks.append(Task { [weak self] in
            for await _ in Defaults.updates(Defaults.Keys.all, initial: false) {
                guard let self else { return }
                let current = DefaultsChangeLog.snapshot()
                DefaultsChangeLog.logChanges(from: lastLoggedDefaults, to: current)
                lastLoggedDefaults = current
            }
        })

        observationTasks.append(Task { [weak self] in
            for await _ in Defaults.updates(Defaults.Keys.badges) {
                guard let self else { return }
                updateDisplayedNotificationCount()
            }
        })
    }

    deinit {
        observationTasks.forEach { $0.cancel() }
    }

    func setSession(_ session: (any FASession)?) async throws {
        guard self.session !== session else { return }
        if session != nil {
            assert(self.session == nil, "Session set twice")
        }
        
        self.session = session
        try await processNewSession()
    }
    
    private func getSession(function: String = #function) throws -> any FASession {
        guard let session else {
            logger.error("Tried to get session in \(function) but there is no active session, throwing")
            throw ModelError.disconnected
        }
        return session
    }
    
    func updateAppInfo() async {
        do {
            try await appInfo.fetch()
            lastAppInfoUpdate = Date()
        } catch {
            // not a big deal if the above failed, no need to notify
        }
    }
    
    private func processNewSession() async throws {
        guard session != nil else {
            lastSubmissionPreviewsFetchDate = nil
            submissionPreviews = nil
            submissionDeletion.reset()
            lastInboxNotePreviewsFetchDate = nil
            notePreviews = [:]
            displayedUnreadNoteCount = 0
            notificationPreviews = nil
            notificationDeletion.reset()
            lastNotificationPreviewsFetchDate = nil
            displayedNotificationCount = 0
            shouldCheckForNewerSubmissionsAfterRestore = false
            searchResults = nil
            searchCanLoadMore = false
            isLoadingSearch = false
            searchLoadFailed = false
            Defaults[.lastViewedSubmissionID] = nil
            return
        }
        
        _ = try await fetchSubmissionPreviews()
        _ = try await fetchNotePreviews(from: .inbox)
        try await fetchNotificationPreviews()
        await updateAppInfo()
    }
    
    static func shouldAutoRefresh(with lastRefreshDate: Date?) -> Bool {
        if let lastRefreshDate {
            let secondsSinceLastRefresh = -lastRefreshDate.timeIntervalSinceNow
            guard secondsSinceLastRefresh > Self.autorefreshDelay else {
                return false
            }
        }
        return true
    }
    
    /// Re-checks stale data when the app returns to the foreground, driven by
    /// `ForegroundAutorefresh` on each platform's logged-in root.
    func autorefreshIfNeeded() async {
        // Without this, a foreground event while logged out raises an error banner.
        guard session != nil else { return }

        // Note how submission previews are not checked here. This is for two reasons:
        // - SubmissionsFeedView has special scroll handling and needs to control
        // when refresh happens
        // - SubmissionsFeedView is always loaded first, so there's no risk that it
        // cannot subscribe to willEnterForegroundNotification

        if Self.shouldAutoRefresh(with: lastInboxNotePreviewsFetchDate) {
            await storeLocalizedError(in: errorStorage, action: "Notes Auto-Refresh", webBrowserURL: FAURLs.notesInboxUrl) {
                _ = try await fetchNotePreviews(from: .inbox)
            }
        }
        
        if Self.shouldAutoRefresh(with: lastNotificationPreviewsFetchDate) {
            await storeLocalizedError(in: errorStorage, action: "Notifications Auto-Refresh", webBrowserURL: FAURLs.notesInboxUrl) {
                try await fetchNotificationPreviews()
            }
        }
        
        if Self.shouldAutoRefresh(with: lastAppInfoUpdate) {
            await updateAppInfo()
        }
    }
    
    // MARK: - Submissions feed
    /// Where the feed's first fetch starts. Autologin establishes the session from
    /// that same page, so the fetch costs no request.
    var firstFeedPosition: Int? { Defaults[.lastViewedSubmissionID] }

    func fetchSubmissionPreviews() async throws -> Int {
        let session = try getSession()
        
        var firstWantedSubmissionID: Int?
        if submissionPreviews == nil {
            firstWantedSubmissionID = firstFeedPosition
        }
        
        var latestSubmissions = try await session.submissionPreviews(from: firstWantedSubmissionID)
        if latestSubmissions.isEmpty, let firstWantedSubmissionID {
            assert(submissionPreviews == nil)
            // Happens if submissions have been nuked
            logger.info("Fetching submissions from \(firstWantedSubmissionID) and older gave no result. Falling back to latest submissions.")
            latestSubmissions = try await session.submissionPreviews(from: nil)
        } else if submissionPreviews == nil, firstWantedSubmissionID != nil {
            // Cold-launch restore from a persisted position succeeded: flag a
            // follow-up check for submissions newer than the restored top.
            shouldCheckForNewerSubmissionsAfterRestore = true
        }
        lastSubmissionPreviewsFetchDate = Date()
        let lastKnownSid = submissionPreviews?.first?.sid ?? 0
        // We take advantage of the fact that submission IDs are always increasing
        // to know which one are new.
        let newSubmissions = OrderedSet(latestSubmissions)
            .filter { $0.sid > lastKnownSid }
        // We also take into account any preview deletion that may have happened since the fetch started
            .filter { preview in !submissionDeletion.hides { $0 == preview } }
        
        if !newSubmissions.isEmpty {
            submissionPreviews = OrderedSet(newSubmissions).appending(contentsOf: submissionPreviews ?? [])
        } else if submissionPreviews == nil {
            submissionPreviews = []
        }
        return newSubmissions.count
    }
    
    func deleteSubmissionPreviews(_ previews: [FASubmissionPreview]) {
        stageSubmissionPreviewsDeletion(previews)
        submissionDeletion.commit()
    }

    func stageSubmissionPreviewsDeletion(_ previews: [FASubmissionPreview]) {
        precondition(submissionPreviews != nil)
        for preview in previews {
            submissionPreviews!.remove(preview)
        }
        submissionDeletion.stage(previews)
    }

    private func reinsertSubmissionPreviews(_ previews: [FASubmissionPreview]) {
        let rows = ((submissionPreviews ?? []) + previews)
            .sorted()
            .reversed()
        submissionPreviews = OrderedSet(rows)
    }
    
    func nukeAllSubmissions() async {
        do {
            try await getSession().nukeSubmissions()
            lastSubmissionPreviewsFetchDate = Date()
            submissionPreviews = []
            submissionDeletion.reset()
        } catch {
            logger.error("Failed nuking submissions: \(error)")
        }
    }

    // MARK: - Exploration (search)

    /// Runs a fresh search (page 1), replacing any previous results, and persists
    /// the criteria so they are remembered next launch.
    func searchSubmissions(_ query: FASearchQuery) async {
        var query = query
        query.page = 1
        searchQuery = query
        Defaults[.lastSearchQuery] = query
        searchResults = nil
        searchCanLoadMore = false
        await fetchSearchResults(replacing: true)
    }

    /// Fetches the next page and appends it. No-op when there's nothing more or a
    /// fetch is already running.
    func loadMoreSearchResults() async {
        guard searchCanLoadMore, !isLoadingSearch else { return }
        let previousPage = searchQuery.page
        searchQuery.page += 1
        // Roll the page back on failure so a retry re-fetches the same page
        // instead of skipping it.
        if await !fetchSearchResults(replacing: false) {
            searchQuery.page = previousPage
        }
    }

    /// Pull-to-refresh: re-runs the current query from page 1 without clearing the
    /// visible results first, so the list stays put under the refresh spinner.
    func refreshSearch() async {
        searchQuery.page = 1
        searchCanLoadMore = false
        await fetchSearchResults(replacing: true)
    }

    /// Returns `true` if the fetch succeeded.
    @discardableResult
    private func fetchSearchResults(replacing: Bool) async -> Bool {
        isLoadingSearch = true
        searchLoadFailed = false
        defer { isLoadingSearch = false }

        var succeeded = false
        await storeLocalizedError(in: errorStorage, action: "Search", webBrowserURL: FAURLs.searchUrl(for: searchQuery)) {
            let results = try await getSession().search(searchQuery)
            let previews = results.previews
            searchAllowedRatings = results.allowedRatings
            searchShowingRecentUploads = results.displayingRecentUploads
            // A full page means more may exist; a short page means we've reached the end.
            searchCanLoadMore = previews.count >= FAURLs.searchPageSize
            if replacing {
                searchResults = OrderedSet(previews)
            } else {
                searchResults = (searchResults ?? []).appending(contentsOf: previews)
            }
            succeeded = true
        }
        searchLoadFailed = !succeeded
        return succeeded
    }
    
    // MARK: - Commentable
    func postComment<C: Commentable>(on commentable: C, replytoCid: Int?, contents: String) async throws -> C {
        try await getSession()
            .postComment(on: commentable, replytoCid: replytoCid, contents: contents)
    }
    
    // MARK: - Notes
    @discardableResult
    func fetchNotePreviews(from box: NotesBox) async throws -> [FANotePreview] {
        let fetchedNotes = try await getSession().notePreviews(from: box)
        setLocalNotePreviews(fetchedNotes, in: box)
        return fetchedNotes
    }
    
    func moveNotes(_ notes: [FANotePreview], from source: NotesBox, to destination: NotesBox) async throws {
        let updated = try await getSession().moveNotes(notes, to: destination)
        setLocalNotePreviews(updated, in: source)
    }
    
    func markNotesAsUnread(_ notes: [FANotePreview], in box: NotesBox) async throws {
        let updated = try await getSession().markNotesAsUnread(notes)
        setLocalNotePreviews(updated, in: box)
    }
    
    func markNoteAsReadLocally(_ note: FANote) {
        var targetBox: (box: NotesBox, previews: [FANotePreview], noteIdx: Int)?
        for (box, previews) in notePreviews {
            if let noteIdx = previews.firstIndex(where: { $0.noteUrl == note.url }) {
                targetBox = (box, previews, noteIdx)
                break
            }
        }

        // Note: none of the sent notes can be marked as read. There can also
        // be notes in archive/trash boxes that will not be marked as read on server (the notes in these boxes sent by the current user).
        // We're a bit optimistic here and consider that all notes can be marked
        // as read, except for sent notes where we know that it's never possible.
        guard let targetBox, targetBox.box != .sent else {
            return
        }
        
        var previews = targetBox.previews
        previews[targetBox.noteIdx] = previews[targetBox.noteIdx].asRead()
        notePreviews[targetBox.box] = previews
        updateDisplayedNotificationCount()
    }

    private func setLocalNotePreviews(_ previews: [FANotePreview], in box: NotesBox) {
        notePreviews[box] = previews
        if box == .inbox {
            lastInboxNotePreviewsFetchDate = Date()
        }
        updateDisplayedNotificationCount()
    }
    
    // MARK: - Notifications feed
    func fetchNotificationPreviews() async throws {
        try await fetchNotificationPreviews { session in
            try await session.notificationPreviews()
        }
    }
    
    var notificationPreviewsSourceUrl: URL {
        FAURLs.notificationsUrl
    }
    
    func deleteNotifications(_ notifications: [FANotificationPreview], of kind: NotificationKind) {
        stageNotificationsDeletion(notifications, of: kind)
        notificationDeletion.commit()
    }

    func stageNotificationsDeletion(_ notifications: [FANotificationPreview], of kind: NotificationKind) {
        guard let notificationPreviews else { return }
        let section = notificationPreviews[kind]
        let staged = notifications.compactMap { preview in
            section.firstIndex(of: preview).map {
                StagedNotification(kind: kind, preview: preview, index: $0)
            }
        }
        self.notificationPreviews = notificationPreviews.removing(notifications, of: kind)
        updateDisplayedNotificationCount()
        notificationDeletion.stage(staged)
    }

    private func sendNotificationsDeletion(_ items: [StagedNotification]) async throws {
        guard let kind = items.first?.kind else { return }
        let notifications = items.map(\.preview)
        do {
            try await fetchNotificationPreviews { session in
                switch kind {
                case .submissionComment:
                    try await session.deleteSubmissionCommentNotifications(notifications)
                case .journalComment:
                    try await session.deleteJournalCommentNotifications(notifications)
                case .shout:
                    try await session.deleteShoutNotifications(notifications)
                case .journal:
                    try await session.deleteJournalNotifications(notifications)
                }
            }
        } catch {
            storeError(error, in: errorStorage, action: "Delete Notification(s)", webBrowserURL: nil)
            throw error
        }
    }

    private func restoreNotifications(_ items: [StagedNotification]) {
        guard let notificationPreviews else { return }
        self.notificationPreviews = notificationPreviews.mapSections { kind, section in
            var section = section
            for item in items.filter({ $0.kind == kind }).sorted(by: { $0.index < $1.index })
            where !section.contains(where: { $0.id == item.preview.id }) {
                section.insert(item.preview, at: min(item.index, section.count))
            }
            return section
        }
        updateDisplayedNotificationCount()
    }

    func nukeAllSubmissionCommentNotifications() async throws {
        try await nukeNotifications { try await $0.nukeAllSubmissionCommentNotifications() }
    }

    func nukeAllJournalCommentNotifications() async throws {
        try await nukeNotifications { try await $0.nukeAllJournalCommentNotifications() }
    }

    func nukeAllShoutNotifications() async throws {
        try await nukeNotifications { try await $0.nukeAllShoutNotifications() }
    }

    func nukeAllJournalNotifications() async throws {
        try await nukeNotifications { try await $0.nukeAllJournalNotifications() }
    }

    private func nukeNotifications(_ nuke: @MainActor (_ session: any FASession) async throws -> FANotificationPreviews) async throws {
        await notificationDeletion.commit()?.value
        try await fetchNotificationPreviews(fetcher: nuke)
    }

    private func fetchNotificationPreviews(fetcher: @MainActor (_ session: any FASession) async throws -> FANotificationPreviews) async throws {
        notificationPreviews = try await fetcher(getSession()).mapSections { kind, section in
            section.filter { preview in
                !notificationDeletion.hides { $0.kind == kind && $0.preview.id == preview.id }
            }
        }
        lastNotificationPreviewsFetchDate = Date()
        updateDisplayedNotificationCount()
    }
    
    private func updateDisplayedNotificationCount() {
        displayedUnreadNoteCount = Defaults[.badgeNotes] ? unreadInboxNoteCount : 0

        displayedNotificationCount = notificationPreviews
            .flatMap { notifications in
                var count = 0

                if Defaults[.badgeSubmissionComments] {
                    count += notifications.submissionComments.count
                }

                if Defaults[.badgeJournalComments] {
                    count += notifications.journalComments.count
                }

                if Defaults[.badgeShouts] {
                    count += notifications.shouts.count
                }

                if Defaults[.badgeJournals] {
                    count += notifications.journals.count
                }

                return count
            } ?? 0
    }
    
    // MARK: - Submission
    func toggleFavorite(for submission: FASubmission) async throws -> FASubmission {
        let updated = try await getSession().toggleFavorite(for: submission)
        if updated.isFavorite == submission.isFavorite {
            logger.error("\(#function) did not change favorite state: \(submission.isFavorite)")
        }
        return updated
    }
}
