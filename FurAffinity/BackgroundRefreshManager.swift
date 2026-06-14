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

/// A built notification content plus the author whose avatar should become the
/// notification's leading icon at post time. Keeps `buildNotifications` pure (the
/// async avatar download + intent donation happen later in `postLocalNotification`).
struct PendingNotification {
    let content: UNMutableNotificationContent
    let author: String
    /// Submission thumbnail to attach to the notification (nil for non-submissions).
    let thumbnail: DynamicThumbnail?
    /// Submission rating, used to decide whether the attachment must be blurred
    /// (nil for non-submissions).
    let rating: Rating?
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

        let submissions: [FASubmissionPreview]
        let notes: [FANotePreview]
        let previews: FANotificationPreviews
        do {
            submissions = try await session.submissionPreviews(from: nil)
            notes = try await session.notePreviews(from: .inbox)
            previews = try await session.notificationPreviews()
        } catch is CloudflareChallengeRequired {
            logger.warning("CF challenge not resolved in background; posting notification")
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

        guard await postLocalNotification(
            newSubmissions: newSubmissions,
            newNotes: newNotes,
            newSubmissionComments: newSubmissionComments,
            newJournalComments: newJournalComments,
            newShouts: newShouts,
            newJournals: newJournals
        ) else {
            return
        }

        latestNotificationIDs.merge(LatestNotificationIDs(submissions: submissions, notes: notes, previews: previews))
        latestNotificationIDs.save()
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

    static func buildNotifications(
        submissions: [FASubmissionPreview],
        notes: [FANotePreview],
        submissionComments: [FANotificationPreview],
        journalComments: [FANotificationPreview],
        shouts: [FANotificationPreview],
        journals: [FANotificationPreview]
    ) -> [PendingNotification] {
        // Submissions carry a thumbnail attachment instead of an emoji prefix.
        submissions.map { notificationContent(emoji: nil, displayAuthor: $0.displayAuthor, body: $0.title, author: $0.author, url: $0.url, thumbnail: $0.dynamicThumbnail, rating: $0.rating) }
            + notes.filter(\.unread).map { notificationContent(emoji: "✉️", displayAuthor: $0.displayAuthor, body: $0.title, author: $0.author, url: $0.noteUrl) }
            + submissionComments.map { notificationContent(emoji: "💬", displayAuthor: $0.displayAuthor, body: $0.title, author: $0.author, url: $0.url) }
            + journalComments.map { notificationContent(emoji: "💬", displayAuthor: $0.displayAuthor, body: $0.title, author: $0.author, url: $0.url) }
            + shouts.map { notificationContent(emoji: "📣", displayAuthor: $0.displayAuthor, body: $0.title, author: $0.author, url: $0.url) }
            + journals.map { notificationContent(emoji: "📝", displayAuthor: $0.displayAuthor, body: $0.title, author: $0.author, url: $0.url) }
    }

    private static func notificationContent(emoji: String?, displayAuthor: String, body: String, author: String, url: URL, thumbnail: DynamicThumbnail? = nil, rating: Rating? = nil) -> PendingNotification {
        let content = UNMutableNotificationContent()
        // Communication-notification enrichment replaces the header with the author
        // name; we set the same title so the text-only fallback (no avatar / missing
        // entitlement) renders the same layout.
        content.title = displayAuthor
        // Prepend a type emoji when present: enrichment drops `title`, so the emoji is
        // what conveys the notification type (note/journal/…) in the message line.
        // Submissions pass `nil` since their thumbnail attachment carries that meaning.
        if let emoji {
            content.body = "\(emoji) \(body)"
        } else {
            content.body = body
        }
        // Carry the FA URL so a tap can deep-link to the related content.
        content.userInfo = [NotificationDeepLink.urlKey: url.absoluteString]
        return PendingNotification(content: content, author: author, thumbnail: thumbnail, rating: rating)
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
    private static func communicationContent(for pending: PendingNotification) async -> UNNotificationContent {
        guard let avatar = await avatarImage(for: pending.author) else {
            return pending.content
        }

        let sender = INPerson(
            personHandle: INPersonHandle(value: pending.author, type: .unknown),
            nameComponents: nil,
            displayName: pending.content.title,
            image: avatar,
            contactIdentifier: nil,
            customIdentifier: pending.author,
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
            content: pending.content.body,
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
            return try pending.content.updating(from: intent)
        } catch {
            logger.error("Failed to enrich notification with avatar intent: \(error)")
            return pending.content
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
    private static func submissionAttachment(thumbnail: DynamicThumbnail, rating: Rating) async -> [UNNotificationAttachment]? {
        let url = thumbnail.bestThumbnailUrl(for: CGSize(width: 400, height: 400))
        guard await kingfisherImageDataProvider(url) != nil else {
            return nil
        }
        guard let file = cachedImageFileURL(for: url) else {
            return nil
        }

        do {
            if rating == .general {
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

    /// Posts each pending notification in order, bailing before the next item once
    /// `isCancelled` returns `true` (so the scarce post-CF budget isn't spent preparing
    /// media that won't be delivered). Pure with respect to its injected closures, so
    /// the cancellation/watermark semantics can be unit-tested without a live
    /// `UNUserNotificationCenter` or network.
    static func flush(
        _ pendings: [PendingNotification],
        isCancelled: () -> Bool,
        post: (PendingNotification) async -> PostResult
    ) async -> FlushOutcome {
        var postedCount = 0
        for pending in pendings {
            if isCancelled() {
                return FlushOutcome(postedCount: postedCount, cancelled: true)
            }
            switch await post(pending) {
            case .posted:
                postedCount += 1
            case .skipped:
                continue
            case .cancelled:
                return FlushOutcome(postedCount: postedCount, cancelled: true)
            }
        }
        return FlushOutcome(postedCount: postedCount, cancelled: false)
    }

    private static func postLocalNotification(
        newSubmissions: [FASubmissionPreview],
        newNotes: [FANotePreview],
        newSubmissionComments: [FANotificationPreview],
        newJournalComments: [FANotificationPreview],
        newShouts: [FANotificationPreview],
        newJournals: [FANotificationPreview]
    ) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            logger.info(
                "Skipping local notification because authorization status is \(settings.authorizationStatus.rawValue)"
            )
            return false
        }

        let filtered = applyPreferences(
            newSubmissions: newSubmissions,
            newNotes: newNotes,
            newSubmissionComments: newSubmissionComments,
            newJournalComments: newJournalComments,
            newShouts: newShouts,
            newJournals: newJournals
        )

        let pendings = buildNotifications(
            submissions: filtered.submissions,
            notes: filtered.notes,
            submissionComments: filtered.submissionComments,
            journalComments: filtered.journalComments,
            shouts: filtered.shouts,
            journals: filtered.journals
        )
        guard !pendings.isEmpty else { return false }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let outcome = await flush(pendings, isCancelled: { Task.isCancelled }) { pending in
            // Set sound on the mutable content before enrichment so it carries into
            // the immutable content returned by updating(from:).
            if settings.soundSetting == .enabled {
                pending.content.sound = .default
            }
            var content = await communicationContent(for: pending)
            // Attach the submission thumbnail (blurred for non-general). Set it on a
            // mutable copy of the enriched content: updating(from:) returns immutable
            // content and may drop attachments, so this is the robust path.
            if let thumbnail = pending.thumbnail, let rating = pending.rating,
               let attachments = await submissionAttachment(thumbnail: thumbnail, rating: rating),
               let mutable = content.mutableCopy() as? UNMutableNotificationContent {
                mutable.attachments = attachments
                // The category routes the notification to the content extension that
                // reveals the clear image on expand. Set here (post-enrichment) since
                // updating(from:) can reset it.
                mutable.categoryIdentifier = submissionCategoryIdentifier
                content = mutable
            }
            // Cancellation can land mid-preparation: the avatar/thumbnail downloads
            // above return cancelled, so posting now would deliver a media-less
            // notification. Defer instead of posting an incomplete one.
            if Task.isCancelled {
                return .cancelled
            }
            let request = UNNotificationRequest(identifier: "fa.background.refresh-\(UUID())", content: content, trigger: trigger)
            do {
                try await center.add(request)
                return .posted
            } catch {
                logger.error("Failed to schedule local notification: \(error)")
                return .skipped
            }
        }
        if outcome.postedCount > 0 {
            logger.info("Scheduled \(outcome.postedCount) local notification(s) for background refresh")
        }
        // Advance the watermark only for a run that completed without cancellation and
        // actually delivered something. A cancelled run leaves the watermark untouched
        // so its unposted items are rediscovered (and re-posted) on the next run.
        return !outcome.cancelled && outcome.postedCount > 0
    }
}

