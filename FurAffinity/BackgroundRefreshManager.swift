//
//  BackgroundRefreshManager.swift
//  FurAffinity
//
//  Created by Ceylo on 24/05/2026.
//

import BackgroundTasks
import Defaults
import FAKit
import Intents
import UserNotifications

private struct LatestNotificationIDs {
    var submissionID: Int
    var noteID: Int
    var submissionCommentID: Int
    var journalCommentID: Int
    var shoutID: Int
    var journalID: Int

    static func load() -> Self {
        Self(
            submissionID: Defaults[.latestSubmissionNotificationID],
            noteID: Defaults[.latestNoteNotificationID],
            submissionCommentID: Defaults[.latestSubmissionCommentNotificationID],
            journalCommentID: Defaults[.latestJournalCommentNotificationID],
            shoutID: Defaults[.latestShoutNotificationID],
            journalID: Defaults[.latestJournalNotificationID]
        )
    }

    mutating func merge(_ other: Self) {
        submissionID = max(submissionID, other.submissionID)
        noteID = max(noteID, other.noteID)
        submissionCommentID = max(submissionCommentID, other.submissionCommentID)
        journalCommentID = max(journalCommentID, other.journalCommentID)
        shoutID = max(shoutID, other.shoutID)
        journalID = max(journalID, other.journalID)
    }

    func save() {
        Defaults[.latestSubmissionNotificationID] = submissionID
        Defaults[.latestNoteNotificationID] = noteID
        Defaults[.latestSubmissionCommentNotificationID] = submissionCommentID
        Defaults[.latestJournalCommentNotificationID] = journalCommentID
        Defaults[.latestShoutNotificationID] = shoutID
        Defaults[.latestJournalNotificationID] = journalID
    }
}

extension LatestNotificationIDs {
    init(submissions: [FASubmissionPreview], notes: [FANotePreview], previews: FANotificationPreviews?) {
        self.init(
            submissionID: submissions.latestID,
            noteID: notes.latestID,
            submissionCommentID: previews?.submissionComments.latestID ?? 0,
            journalCommentID: previews?.journalComments.latestID ?? 0,
            shoutID: previews?.shouts.latestID ?? 0,
            journalID: previews?.journals.latestID ?? 0
        )
    }
}

extension Collection where Element: Identifiable, Element.ID == Int {
    fileprivate var latestID: Int {
        map(\.id).max() ?? 0
    }
}

/// Everything needed to rebuild and post one notification without re-parsing FA
/// pages. Persisted (via `Defaults[.pendingNotificationQueue]`) at a checkpoint
/// before the slow media+post phase, so a background run expired mid-flight resumes
/// the remainder next time instead of redoing or losing it.
struct PendingNotificationRecord: Codable, Defaults.Serializable, Equatable {
    /// Stable per-item key (e.g. `"submission-123"`, `"shout-456"`) — prevents the
    /// same item being enqueued twice across discovery passes.
    let dedupKey: String
    /// Notification header (the author's display name).
    let title: String
    /// Final message body, with any type emoji prefix already applied.
    let body: String
    /// Author handle, used to download the avatar at post time.
    let author: String
    /// Deep-link URL string carried in `userInfo`.
    let url: String
    /// Resolved best 400px thumbnail URL (submissions only; nil otherwise).
    let thumbnailURLString: String?
    /// Whether the thumbnail attachment must be blurred (rating != .general).
    let needsBlur: Bool
}

private final class BackgroundRefreshTaskRunner: @unchecked Sendable {
    private let task: BGAppRefreshTask
    private let lock = NSLock()
    private var hasCompleted = false
    private var refreshTask: Task<Void, Never>?

    init(task: BGAppRefreshTask) {
        self.task = task
    }

    func start() {
        refreshTask = Task {
            let success: Bool
            do {
                try await BackgroundRefreshManager.performFetchAndNotify()
                success = !Task.isCancelled
            } catch is CancellationError {
                success = false
            } catch {
                logger.error("Background refresh failed: \(error)")
                success = false
            }
            complete(success: success)
        }
    }

    func cancel() {
        refreshTask?.cancel()
        complete(success: false)
    }

    private func complete(success: Bool) {
        lock.withLock {
            guard !hasCompleted else {
                return
            }
            hasCompleted = true
            task.setTaskCompleted(success: success)
        }
    }
}

// This manager registers, schedules and handles a BGAppRefresh task
// to fetch FA notifications and post a local notification when new
// items are available, honoring the user's toggles in Settings.
enum BackgroundRefreshManager {
    // Identifier must be added to Info.plist (BGTaskSchedulerPermittedIdentifiers)
    static var taskIdentifier: String { (Bundle.main.bundleIdentifier ?? "app") + ".background-refresh" }

    /// Notification category for submission notifications. Matched by the
    /// NotificationContent app extension (`UNNotificationExtensionCategory`) so a
    /// long-press / expand reveals the clear thumbnail.
    static let submissionCategoryIdentifier = "fa.submission"

    /// Registers the notification categories handled by the app's content extension.
    /// Called at startup so the extension is wired up before any notification posts.
    static func registerNotificationCategories() {
        let submission = UNNotificationCategory(
            identifier: submissionCategoryIdentifier,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([submission])
    }

    // MARK: Registration & Scheduling
    static func register() {
        registerNotificationCategories()

        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let appRefreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(appRefreshTask)
        }
        if registered {
            logger.info("Registered background task: \(self.taskIdentifier)")
        } else {
            logger.error("Failed to register background task: \(self.taskIdentifier)")
        }
    }

    static func updateLatestFetchedNotificationIDs(
        submissions: [FASubmissionPreview],
        notes: [FANotePreview],
        notifications: FANotificationPreviews?
    ) {
        guard !submissions.isEmpty || !notes.isEmpty || notifications != nil else {
            return
        }

        var latestNotificationIDs = LatestNotificationIDs.load()
        latestNotificationIDs.merge(LatestNotificationIDs(submissions: submissions, notes: notes, previews: notifications))
        latestNotificationIDs.save()
    }

    static func schedule(earliestBeginAfter seconds: TimeInterval = 30 * 60) {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: seconds)
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled background refresh (earliest in \(Int(seconds))s)")
        } catch {
            logger.error("Failed scheduling background refresh: \(error)")
        }
    }

    // MARK: Task handling
    private static func handle(_ task: BGAppRefreshTask) {
        // Always reschedule for the next time
        schedule()

        let runner = BackgroundRefreshTaskRunner(task: task)
        runner.start()

        task.expirationHandler = {
            logger.warning("Background refresh expired by the system")
            runner.cancel()
        }
    }

    // MARK: Notification Authorization
    static func requestNotificationAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else {
            return
        }

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            logger.info("Notification authorization granted? \(granted)")
        } catch {
            logger.error("Notification auth error: \(error)")
        }
    }

    // MARK: Fetch & Notify
    static func performFetchAndNotify() async throws {
        guard let session = try await FALoginView.makeSession() else {
            logger.info("No valid FA session for background refresh (user likely logged out)")
            return
        }

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            logger.info(
                "Skipping background refresh because authorization status is \(settings.authorizationStatus.rawValue)"
            )
            return
        }
        let soundEnabled = settings.soundSetting == .enabled

        let submissions: [FASubmissionPreview]
        let notes: [FANotePreview]
        let previews: FANotificationPreviews
        do {
            submissions = try await session.submissionPreviews(from: nil)
            notes = try await session.notePreviews(from: .inbox)
            previews = try await session.notificationPreviews()
        } catch is CloudflareChallengeRequired {
            logger.warning("CF challenge not resolved in background; posting notification")
            // Leave the pending queue intact so a previously-stranded remainder isn't lost.
            await postChallengeFailureNotification()
            return
        }

        var latestNotificationIDs = LatestNotificationIDs.load()

        let newSubmissions = submissions.filter { $0.id > latestNotificationIDs.submissionID }
        let newNotes = notes.filter { $0.id > latestNotificationIDs.noteID }
        let newSubmissionComments = previews.submissionComments.filter {
            $0.id > latestNotificationIDs.submissionCommentID
        }
        let newJournalComments = previews.journalComments.filter { $0.id > latestNotificationIDs.journalCommentID }
        let newShouts = previews.shouts.filter { $0.id > latestNotificationIDs.shoutID }
        let newJournals = previews.journals.filter { $0.id > latestNotificationIDs.journalID }

        let filtered = applyPreferences(
            newSubmissions: newSubmissions,
            newNotes: newNotes,
            newSubmissionComments: newSubmissionComments,
            newJournalComments: newJournalComments,
            newShouts: newShouts,
            newJournals: newJournals
        )
        let records = buildRecords(
            submissions: filtered.submissions,
            notes: filtered.notes,
            submissionComments: filtered.submissionComments,
            journalComments: filtered.journalComments,
            shouts: filtered.shouts,
            journals: filtered.journals
        )

        // Checkpoint that survives expiration: advance the watermark to everything
        // fetched and persist the (deduped) queue *before* the slow media+post phase.
        // The queue is now the source of truth for what still needs posting, so a run
        // expired mid-flush resumes the remainder instead of redoing or losing it.
        Defaults[.pendingNotificationQueue] = enqueue(records, into: Defaults[.pendingNotificationQueue])
        latestNotificationIDs.merge(LatestNotificationIDs(submissions: submissions, notes: notes, previews: previews))
        latestNotificationIDs.save()

        await flushQueue(soundEnabled: soundEnabled)
    }

    static func applyPreferences(
        newSubmissions: [FASubmissionPreview],
        newNotes: [FANotePreview],
        newSubmissionComments: [FANotificationPreview],
        newJournalComments: [FANotificationPreview],
        newShouts: [FANotificationPreview],
        newJournals: [FANotificationPreview]
    ) -> (
        submissions: [FASubmissionPreview],
        notes: [FANotePreview],
        submissionComments: [FANotificationPreview],
        journalComments: [FANotificationPreview],
        shouts: [FANotificationPreview],
        journals: [FANotificationPreview]
    ) {
        (
            submissions: Defaults[.notifySubmissions] ? newSubmissions : [],
            notes: Defaults[.notifyNotes] ? newNotes : [],
            submissionComments: Defaults[.notifySubmissionComments] ? newSubmissionComments : [],
            journalComments: Defaults[.notifyJournalComments] ? newJournalComments : [],
            shouts: Defaults[.notifyShouts] ? newShouts : [],
            journals: Defaults[.notifyJournals] ? newJournals : []
        )
    }

    static func buildRecords(
        submissions: [FASubmissionPreview],
        notes: [FANotePreview],
        submissionComments: [FANotificationPreview],
        journalComments: [FANotificationPreview],
        shouts: [FANotificationPreview],
        journals: [FANotificationPreview]
    ) -> [PendingNotificationRecord] {
        // Submissions carry a thumbnail attachment instead of an emoji prefix.
        submissions.map { submissionRecord($0) }
            + notes.filter(\.unread).map { record(emoji: "✉️", dedupKey: "note-\($0.id)", displayAuthor: $0.displayAuthor, body: $0.title, author: $0.author, url: $0.noteUrl) }
            + submissionComments.map { record(emoji: "💬", dedupKey: "submission-comment-\($0.id)", displayAuthor: $0.displayAuthor, body: $0.title, author: $0.author, url: $0.url) }
            + journalComments.map { record(emoji: "💬", dedupKey: "journal-comment-\($0.id)", displayAuthor: $0.displayAuthor, body: $0.title, author: $0.author, url: $0.url) }
            + shouts.map { record(emoji: "📣", dedupKey: "shout-\($0.id)", displayAuthor: $0.displayAuthor, body: $0.title, author: $0.author, url: $0.url) }
            + journals.map { record(emoji: "📝", dedupKey: "journal-\($0.id)", displayAuthor: $0.displayAuthor, body: $0.title, author: $0.author, url: $0.url) }
    }

    private static func submissionRecord(_ submission: FASubmissionPreview) -> PendingNotificationRecord {
        // Resolve the same 400px thumbnail the attachment builder consumes, now so it
        // can be persisted and downloaded later without the FAKit type.
        let thumbnailURL = submission.dynamicThumbnail.bestThumbnailUrl(for: CGSize(width: 400, height: 400))
        return record(
            emoji: nil,
            dedupKey: "submission-\(submission.id)",
            displayAuthor: submission.displayAuthor,
            body: submission.title,
            author: submission.author,
            url: submission.url,
            thumbnailURLString: thumbnailURL.absoluteString,
            needsBlur: submission.rating != .general
        )
    }

    private static func record(emoji: String?, dedupKey: String, displayAuthor: String, body: String, author: String, url: URL, thumbnailURLString: String? = nil, needsBlur: Bool = false) -> PendingNotificationRecord {
        // Prepend a type emoji when present: communication enrichment drops `title`, so
        // the emoji is what conveys the notification type (note/journal/…) in the
        // message line. Submissions pass `nil` since their thumbnail carries that meaning.
        let finalBody = emoji.map { "\($0) \(body)" } ?? body
        return PendingNotificationRecord(
            dedupKey: dedupKey,
            // Communication enrichment replaces the header with the author name; we set
            // the same title so the text-only fallback renders the same layout.
            title: displayAuthor,
            body: finalBody,
            author: author,
            url: url.absoluteString,
            thumbnailURLString: thumbnailURLString,
            needsBlur: needsBlur
        )
    }

    /// Appends `records` to `queue`, skipping any whose `dedupKey` is already present.
    static func enqueue(
        _ records: [PendingNotificationRecord],
        into queue: [PendingNotificationRecord]
    ) -> [PendingNotificationRecord] {
        let existingKeys = Set(queue.map(\.dedupKey))
        return queue + records.filter { !existingKeys.contains($0.dedupKey) }
    }

    /// Identifier for the CloudFlare-challenge failure local notification.
    static let challengeFailureNotificationIdentifier = "fa.background.cf-challenge"

    /// Builds the content for the CloudFlare-challenge failure notification.
    /// Pure (no `UNUserNotificationCenter`), mirroring `buildNotifications`; sound
    /// is applied at post time in `postChallengeFailureNotification`.
    static func buildChallengeFailureNotification() -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "CloudFlare check required"
        content.body = "FurAffinity needs human verification. Open the app to resume notifications."
        return content
    }

    private static func postChallengeFailureNotification() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let content = buildChallengeFailureNotification()
        if settings.soundSetting == .enabled {
            content.sound = .default
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: challengeFailureNotificationIdentifier,
            content: content,
            trigger: trigger
        )
        do {
            try await center.add(request)
            logger.info("Posted CF challenge notification")
        } catch {
            logger.error("Failed to post CF challenge notification: \(error)")
        }
    }

    /// Fetches the author's avatar (ensuring it is cached via Kingfisher) and wraps
    /// it as an `INImage` for use as a communication-notification sender image.
    /// Returns `nil` when the author has no avatar URL or the download/cache fails.
    private static func avatarImage(for author: String) async -> INImage? {
        guard let url = FAURLs.avatarUrl(for: author) else {
            return nil
        }
        guard await kingfisherImageDataProvider(url) != nil else {
            return nil
        }
        guard let file = cachedImageFileURL(for: url) else {
            return nil
        }
        return INImage(url: file)
    }

    /// Enriches a pending notification into a Communication Notification whose leading
    /// icon is the author's avatar, by donating an `INSendMessageIntent` and applying
    /// it to the content. Falls back to the original text-only content when the avatar
    /// can't be fetched or the enrichment fails (e.g. the Communication Notifications
    /// entitlement is missing, which makes `updating(from:)` throw).
    private static func communicationContent(_ content: UNMutableNotificationContent, author: String) async -> UNNotificationContent {
        guard let avatar = await avatarImage(for: author) else {
            return content
        }

        let sender = INPerson(
            personHandle: INPersonHandle(value: author, type: .unknown),
            nameComponents: nil,
            displayName: content.title,
            image: avatar,
            contactIdentifier: nil,
            customIdentifier: author,
            isMe: false,
            suggestionType: .none
        )
        let me = INPerson(
            personHandle: INPersonHandle(value: "me", type: .unknown),
            nameComponents: nil,
            displayName: nil,
            image: nil,
            contactIdentifier: nil,
            customIdentifier: nil,
            isMe: true,
            suggestionType: .none
        )
        let intent = INSendMessageIntent(
            recipients: [me],
            outgoingMessageType: .outgoingMessageText,
            content: content.body,
            speakableGroupName: nil,
            conversationIdentifier: nil,
            serviceName: nil,
            sender: sender,
            attachments: nil
        )
        intent.setImage(avatar, forParameterNamed: \INSendMessageIntent.sender)

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        do {
            try await interaction.donate()
        } catch {
            logger.error("Failed to donate message intent: \(error)")
        }

        do {
            return try content.updating(from: intent)
        } catch {
            logger.error("Failed to enrich notification with avatar intent: \(error)")
            return content
        }
    }

    /// Builds the notification attachment(s) for a submission thumbnail. Ensures the
    /// 400px thumbnail is cached, then returns:
    /// - general: a single clear attachment (identifier `"clear"`), shown everywhere.
    /// - mature/adult: a blurred primary attachment (identifier `"blurred"`, shown on
    ///   the banner / lock screen) plus a hidden clear attachment (identifier `"clear"`,
    ///   `thumbnailHidden`) that the content extension reveals on long-press / expand.
    /// Returns `nil` if the thumbnail can't be fetched, or if blurring fails (so the
    /// unblurred NSFW image is never attached by accident).
    private static func submissionAttachment(thumbnailURL url: URL, needsBlur: Bool) async -> [UNNotificationAttachment]? {
        guard await kingfisherImageDataProvider(url) != nil else {
            return nil
        }
        guard let file = cachedImageFileURL(for: url) else {
            return nil
        }

        do {
            if !needsBlur {
                let clear = try UNNotificationAttachment(identifier: "clear", url: file, options: nil)
                return [clear]
            } else {
                guard let blurredFile = ImageBlur.blurredImageFile(from: file) else {
                    return nil
                }
                // The blurred attachment is first, so it's the primary image on the
                // banner / lock screen. The clear attachment is hidden from the banner
                // thumbnail but bundled so the content extension can reveal it on expand.
                let blurred = try UNNotificationAttachment(identifier: "blurred", url: blurredFile, options: nil)
                let clear = try UNNotificationAttachment(
                    identifier: "clear",
                    url: file,
                    options: [UNNotificationAttachmentOptionsThumbnailHiddenKey: true]
                )
                return [blurred, clear]
            }
        } catch {
            logger.error("Failed to build submission attachment: \(error)")
            return nil
        }
    }

    /// Outcome of flushing the pending notifications. `cancelled` is `true` when the
    /// run was interrupted before posting every item — callers must NOT advance the
    /// notification watermark in that case, or unposted items would be lost forever.
    struct FlushOutcome: Equatable {
        var postedCount: Int
        var cancelled: Bool
    }

    /// Result of attempting to post a single notification.
    /// - `posted`: `center.add` succeeded.
    /// - `skipped`: a genuine failure (e.g. `center.add` threw) — does not defer the run.
    /// - `cancelled`: the task was cancelled mid-preparation, so the content would be
    ///   media-less; the item is left unposted and the run is treated as cancelled.
    enum PostResult {
        case posted
        case skipped
        case cancelled
    }

    /// Flushes the pending queue, preparing each record's media (avatar + thumbnail
    /// downloads) and posting it concurrently, bounded to `maxConcurrent` in-flight so
    /// the scarce post-CF budget delivers media for as many items as possible rather
    /// than one or two. The shrinking remainder is persisted (via `persist`) as each
    /// item is delivered/skipped, so a run interrupted mid-flush resumes from what's
    /// left; an item whose preparation was cancelled is kept queued (`PostResult` is
    /// `.cancelled`) and marks the run cancelled. Pure with respect to its injected
    /// closures, so the concurrency / resume / cancellation bookkeeping can be
    /// unit-tested without a live `UNUserNotificationCenter` or network.
    ///
    /// `post` runs in a child task, so it must be `@Sendable`; `persist` is invoked only
    /// from the consuming parent task (serially), so it needn't be.
    static func flushConcurrently(
        _ queue: [PendingNotificationRecord],
        maxConcurrent: Int,
        post: @escaping @Sendable (PendingNotificationRecord) async -> PostResult,
        persist: ([PendingNotificationRecord]) -> Void
    ) async -> FlushOutcome {
        var remaining = queue
        var postedCount = 0
        var cancelled = false
        var iterator = queue.makeIterator()

        await withTaskGroup(of: (String, PostResult).self) { group in
            func addNext() {
                guard let record = iterator.next() else { return }
                group.addTask { (record.dedupKey, await post(record)) }
            }
            // Prime up to `maxConcurrent` preparations; each completion feeds the next.
            for _ in 0 ..< max(1, min(maxConcurrent, queue.count)) {
                addNext()
            }
            while let (dedupKey, result) = await group.next() {
                switch result {
                case .posted:
                    postedCount += 1
                    remaining.removeAll { $0.dedupKey == dedupKey }
                    persist(remaining)
                case .skipped:
                    // A genuine post failure isn't retried — drop it so it can't clog
                    // the queue.
                    remaining.removeAll { $0.dedupKey == dedupKey }
                    persist(remaining)
                case .cancelled:
                    // Keep it queued for the next run and mark the run cancelled so the
                    // caller doesn't treat a partial flush as complete.
                    cancelled = true
                }
                addNext()
            }
        }
        return FlushOutcome(postedCount: postedCount, cancelled: cancelled)
    }

    /// Clears the persisted pending-notification queue. Called on app use: the user has
    /// now seen the content in-app, and the watermark is advanced to the in-app state at
    /// the same time, so discarded items won't be rediscovered.
    static func discardPendingNotificationQueue() {
        Defaults[.pendingNotificationQueue] = []
    }

    /// Builds the base mutable content for a record (title / emoji-prefixed body /
    /// deep-link / sound) before communication enrichment and attachment.
    private static func baseContent(for record: PendingNotificationRecord, soundEnabled: Bool) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = record.title
        content.body = record.body
        // Carry the FA URL so a tap can deep-link to the related content.
        content.userInfo = [NotificationDeepLink.urlKey: record.url]
        // Set sound on the mutable content before enrichment so it carries into the
        // immutable content returned by updating(from:).
        if soundEnabled {
            content.sound = .default
        }
        return content
    }

    /// Maximum simultaneous media preparations during a flush. Bounds load on the
    /// network / image cache while still overlapping the per-item downloads.
    private static let maxConcurrentPreparations = 6

    /// Prepares a record's final notification content (avatar enrichment + thumbnail
    /// attachment) and posts it, returning whether it posted, was skipped, or was
    /// cancelled mid-preparation. Runs in a child task during a concurrent flush, so it
    /// creates the notification center / trigger itself rather than capturing them
    /// (neither is `Sendable`).
    private static func post(_ record: PendingNotificationRecord, soundEnabled: Bool) async -> PostResult {
        var content = await communicationContent(baseContent(for: record, soundEnabled: soundEnabled), author: record.author)
        // Attach the submission thumbnail (blurred when needed). Set it on a mutable
        // copy of the enriched content: updating(from:) returns immutable content and
        // may drop attachments, so this is the robust path.
        if let urlString = record.thumbnailURLString, let url = URL(string: urlString),
           let attachments = await submissionAttachment(thumbnailURL: url, needsBlur: record.needsBlur),
           let mutable = content.mutableCopy() as? UNMutableNotificationContent {
            mutable.attachments = attachments
            // The category routes the notification to the content extension that
            // reveals the clear image on expand. Set here (post-enrichment) since
            // updating(from:) can reset it.
            mutable.categoryIdentifier = submissionCategoryIdentifier
            content = mutable
        }
        // Cancellation can land mid-preparation: the avatar/thumbnail downloads above
        // return cancelled, so posting now would deliver a media-less notification.
        // Defer instead of posting an incomplete one.
        if Task.isCancelled {
            return .cancelled
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "fa.background.refresh-\(UUID())", content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
            return .posted
        } catch {
            logger.error("Failed to schedule local notification: \(error)")
            return .skipped
        }
    }

    private static func flushQueue(soundEnabled: Bool) async {
        let outcome = await flushConcurrently(
            Defaults[.pendingNotificationQueue],
            maxConcurrent: maxConcurrentPreparations,
            post: { await post($0, soundEnabled: soundEnabled) },
            persist: { Defaults[.pendingNotificationQueue] = $0 }
        )
        if outcome.postedCount > 0 {
            logger.info("Scheduled \(outcome.postedCount) local notification(s) for background refresh")
        }
    }
}

