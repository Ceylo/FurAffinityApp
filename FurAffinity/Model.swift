//
//  Model.swift
//  FurAffinity
//
//  Created by Ceylo on 21/11/2021.
//

import SwiftUI
import FAKit
import Combine
import Defaults

enum ModelError: Error {
    case disconnected
}

@MainActor
class Model: ObservableObject, NotificationsNuker, NotificationsDeleter {
    static private let autorefreshDelay: TimeInterval = 15 * 60
    
    @Published var session: (any FASession)? {
        didSet {
            guard oldValue !== session else { return }
            if session != nil {
                assert(oldValue == nil, "Session set twice")
            }
            processNewSession()
        }
    }

    /// `nil` until a fetch actually happened.
    /// After a fetch it contains all found submissions, or an empty array if none was found.
    @Published
    private(set) var submissionPreviews: [FASubmissionPreview]?
    private(set) var lastSubmissionPreviewsFetchDate: Date?
    
    /// `nil` until a fetch actually happened.
    /// After a fetch it contains all found notes, or an empty array if none was found.
    @Published
    private(set) var inboxNotePreviews: [FANotePreview]?
    @Published
    private(set) var unreadInboxNoteCount = 0
    private(set) var lastInboxNotePreviewsFetchDate: Date?
    
    /// nil until a fetch actually happened
    /// After a fetch it contains all found notifications, or an empty array if none was found
    @Published private(set) var notificationPreviews: FANotificationPreviews?
    @Published private(set) var lastNotificationPreviewsFetchDate: Date?
    @Published private(set) var significantNotificationCount = 0
    
    @Published
    private(set) var appInfo = AppInformation()
    private var lastAppInfoUpdate: Date?

    private var subscriptions = Set<AnyCancellable>()
    private var autorefreshSubscription: AnyCancellable?
    init(session: (any FASession)? = nil) {
        self.session = session
        appInfo.objectWillChange.sink {
            self.objectWillChange.send()
        }
        .store(in: &subscriptions)
        
        Defaults.publisher(keys: Defaults.Keys.all, options: [])
            .sink {
                let userDefaults = UserDefaults.standard
                let preferences = Defaults.Keys.all
                    .compactMap { key in
                        userDefaults.object(forKey: key.name).map { value in
                            (key.name, value)
                        }
                    }
                    .sorted(by: { $0.0 < $1.0 })
                
                logger.info("UserDefaults state update: \(preferences, privacy: .public)")
            }
            .store(in: &subscriptions)
        
        Defaults.publisher(keys: Defaults.Keys.notifications)
            .sink { [unowned self] in
                updateSignificantNotificationCount()
            }
            .store(in: &subscriptions)
        
        processNewSession()
    }
    
    func updateAppInfo() async {
        try? await appInfo.fetch()
        lastAppInfoUpdate = Date()
    }
    
    func clearSessionData() {
        Defaults[.lastViewedSubmissionID] = nil
    }
    
    private func processNewSession() {
        guard session != nil else {
            lastSubmissionPreviewsFetchDate = nil
            submissionPreviews = nil
            lastInboxNotePreviewsFetchDate = nil
            inboxNotePreviews = nil
            unreadInboxNoteCount = 0
            notificationPreviews = nil
            lastNotificationPreviewsFetchDate = nil
            significantNotificationCount = 0
            autorefreshSubscription = nil
            return
        }
        
        Task {
            _ = await fetchSubmissionPreviews()
            _ = try? await fetchNotePreviews(from: .inbox)
            await fetchNotificationPreviews()
            await updateAppInfo()
            
            autorefreshSubscription = NotificationCenter.default
                .publisher(for: UIApplication.willEnterForegroundNotification)
                .sink { [unowned self] _ in
                    Task {
                        await autorefreshIfNeeded()
                    }
                }
        }
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
    
    private func autorefreshIfNeeded() async {
        // Note how submission previews are not checked here. This is for two reasons:
        // - SubmissionsFeedView has special scroll handling and needs to control
        // when refresh happens
        // - SubmissionsFeedView is always loaded first, so there's no risk that it
        // cannot subscribe to willEnterForegroundNotification
        
        if Self.shouldAutoRefresh(with: lastInboxNotePreviewsFetchDate) {
            _ = try? await fetchNotePreviews(from: .inbox)
        }
        
        if Self.shouldAutoRefresh(with: lastNotificationPreviewsFetchDate) {
            await fetchNotificationPreviews()
        }
        
        if Self.shouldAutoRefresh(with: lastAppInfoUpdate) {
            await updateAppInfo()
        }
    }
    
    // MARK: - Submissions feed
    func fetchSubmissionPreviews() async -> Int {
        guard let session else {
            logger.error("Tried to fetch submissions with no active session, skipping")
            return 0
        }
        
        var firstWantedSubmissionID: Int?
        if submissionPreviews == nil {
            firstWantedSubmissionID = Defaults[.lastViewedSubmissionID]
        }
        
        var latestSubmissions = await session.submissionPreviews(from: firstWantedSubmissionID)
        if latestSubmissions.isEmpty, let firstWantedSubmissionID {
            assert(submissionPreviews == nil)
            // Happens if submissions have been nuked
            logger.info("Fetching submissions from \(firstWantedSubmissionID) and older gave no result. Falling back to latest submissions.")
            latestSubmissions = await session.submissionPreviews(from: nil)
        }
        lastSubmissionPreviewsFetchDate = Date()
        let lastKnownSid = submissionPreviews?.first?.sid ?? 0
        // We take advantage of the fact that submission IDs are always increasing
        // to know which one are new.
        let newSubmissions = latestSubmissions.filter { $0.sid > lastKnownSid }
        
        if !newSubmissions.isEmpty {
            submissionPreviews = newSubmissions + (submissionPreviews ?? [])
        } else if submissionPreviews == nil {
            submissionPreviews = []
        }
        return newSubmissions.count
    }
    
    func deleteSubmissionPreviews(atOffsets offsets: IndexSet) {
        precondition(submissionPreviews != nil)
        
        let previews = offsets.map { submissionPreviews![$0] }
        submissionPreviews!.remove(atOffsets: offsets)
        
        Task {
            do {
                let session = try session.unwrap()
                try await session.deleteSubmissionPreviews(previews)
            } catch {
                logger.error("Submission previews deletion failed with error \"\(error, privacy: .public)\", rolling back")
                let rollback = ((submissionPreviews ?? []) + previews)
                    .sorted()
                    .reversed()
                submissionPreviews = rollback
            }
        }
    }
    
    func nukeAllSubmissions() async {
        guard let session else {
            logger.error("Tried to nuke submissions with no active session, skipping")
            return
        }
        
        do {
            try await session.nukeSubmissions()
            lastSubmissionPreviewsFetchDate = Date()
            submissionPreviews = []
        } catch {
            logger.error("Failed nuking submissions: \(error, privacy: .public)")
        }
    }
    
    // MARK: - Commentable
    func postComment<C: Commentable>(on commentable: C, replytoCid: Int?, contents: String) async throws -> C {
        guard let session else {
            throw ModelError.disconnected
        }
        
        return try await session.postComment(on: commentable, replytoCid: replytoCid, contents: contents)
    }
    
    // MARK: - Notes
    @discardableResult
    func fetchNotePreviews(from box: NotesBox) async throws -> [FANotePreview] {
        guard let session else {
            logger.error("Tried to fetch notes with no active session, skipping")
            throw ModelError.disconnected
        }
        
        let fetchedNotes = await session.notePreviews(from: box)
        
        if box == .inbox {
            inboxNotePreviews = fetchedNotes
            unreadInboxNoteCount = fetchedNotes.filter { $0.unread }.count
            lastInboxNotePreviewsFetchDate = Date()
        }
        return fetchedNotes
    }
    
    func markInboxNoteAsRead(_ note: FANote) {
        let idx = inboxNotePreviews?.firstIndex { preview in
            preview.noteUrl == note.url
        }
        if let idx, let inboxNotePreviews {
            self.inboxNotePreviews![idx] = inboxNotePreviews[idx].asRead()
            unreadInboxNoteCount = self.inboxNotePreviews!.filter { $0.unread }.count
        }
    }
    
    // MARK: - Notifications feed
    func fetchNotificationPreviews() async {
        await fetchNotificationPreviews { session in
            await session.notificationPreviews()
        }
    }
        
    func deleteSubmissionCommentNotifications(_ notifications: [FANotificationPreview]) {
        notificationPreviews = notificationPreviews.map { oldNotifications in
            FANotificationPreviews(
                submissionComments: oldNotifications.submissionComments.filter { !notifications.contains($0) },
                journalComments: oldNotifications.journalComments,
                shouts: oldNotifications.shouts,
                journals: oldNotifications.journals
            )
        }
        
        Task {
            await fetchNotificationPreviews { session in
                await session.deleteSubmissionCommentNotifications(notifications)
            }
        }
    }
    
    func deleteJournalCommentNotifications(_ notifications: [FANotificationPreview]) {
        notificationPreviews = notificationPreviews.map { oldNotifications in
            FANotificationPreviews(
                submissionComments: oldNotifications.submissionComments,
                journalComments: oldNotifications.journalComments.filter { !notifications.contains($0) },
                shouts: oldNotifications.shouts,
                journals: oldNotifications.journals
            )
        }
        
        Task {
            await fetchNotificationPreviews { session in
                await session.deleteJournalCommentNotifications(notifications)
            }
        }
    }
    
    func deleteShoutNotifications(_ notifications: [FANotificationPreview]) {
        notificationPreviews = notificationPreviews.map { oldNotifications in
            FANotificationPreviews(
                submissionComments: oldNotifications.submissionComments,
                journalComments: oldNotifications.journalComments,
                shouts: oldNotifications.shouts.filter { !notifications.contains($0) },
                journals: oldNotifications.journals
            )
        }
        
        Task {
            await fetchNotificationPreviews { session in
                await session.deleteShoutNotifications(notifications)
            }
        }
    }
    
    func deleteJournalNotifications(_ notifications: [FANotificationPreview]) {
        notificationPreviews = notificationPreviews.map { oldNotifications in
            FANotificationPreviews(
                submissionComments: oldNotifications.submissionComments,
                journalComments: oldNotifications.journalComments,
                shouts: oldNotifications.shouts,
                journals: oldNotifications.journals.filter { !notifications.contains($0) }
            )
        }
        
        Task {
            await fetchNotificationPreviews { session in
                await session.deleteJournalNotifications(notifications)
            }
        }
    }
    
    func nukeAllSubmissionCommentNotifications() async {
        await fetchNotificationPreviews { session in
            await session.nukeAllSubmissionCommentNotifications()
        }
    }
    
    func nukeAllJournalCommentNotifications() async {
        await fetchNotificationPreviews { session in
            await session.nukeAllJournalCommentNotifications()
        }
    }
    
    func nukeAllShoutNotifications() async {
        await fetchNotificationPreviews { session in
            await session.nukeAllShoutNotifications()
        }
    }
    
    func nukeAllJournalNotifications() async {
        await fetchNotificationPreviews { session in
            await session.nukeAllJournalNotifications()
        }
    }
    
    
    private func fetchNotificationPreviews(fetcher: (_ session: any FASession) async -> FANotificationPreviews) async {
        guard let session else {
            logger.error("Tried to fetch notifications with no active session, skipping")
            return
        }
        
        notificationPreviews = await fetcher(session)
        lastNotificationPreviewsFetchDate = Date()
        updateSignificantNotificationCount()
    }
    
    private func updateSignificantNotificationCount() {
        significantNotificationCount = notificationPreviews
            .flatMap { notifications in
                var count = 0
                
                if Defaults[.notifySubmissionComments] {
                    count += notifications.submissionComments.count
                }
                
                if Defaults[.notifyJournalComments] {
                    count += notifications.journalComments.count
                }
                
                if Defaults[.notifyShouts] {
                    count += notifications.shouts.count
                }
                
                if Defaults[.notifyJournals] {
                    count += notifications.journals.count
                }
                
                return count
            } ?? 0
    }
    
    // MARK: - Submission
    func toggleFavorite(for submission: FASubmission) async throws -> FASubmission {
        guard let session else {
            throw ModelError.disconnected
        }
        
        let updated = try await session.toggleFavorite(for: submission)
        if updated.isFavorite == submission.isFavorite {
            logger.error("\(#function, privacy: .public) did not change favorite state: \(submission.isFavorite)")
        }
        return updated
    }
}
