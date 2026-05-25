//
//  BackgroundRefreshManager.swift
//  FurAffinity
//
//  Created by Ceylo on 24/05/2026.
//

import BackgroundTasks
import Defaults
import FAKit
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

    init(
        submissionID: Int,
        noteID: Int,
        submissionCommentID: Int,
        journalCommentID: Int,
        shoutID: Int,
        journalID: Int
    ) {
        self.submissionID = submissionID
        self.noteID = noteID
        self.submissionCommentID = submissionCommentID
        self.journalCommentID = journalCommentID
        self.shoutID = shoutID
        self.journalID = journalID
    }

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

extension [FANotePreview] {
    fileprivate var latestID: Int {
        map(\.id).max() ?? 0
    }
}

extension [FANotificationPreview] {
    fileprivate var latestID: Int {
        map(\.id).max() ?? 0
    }
}

extension [FASubmissionPreview] {
    fileprivate var latestID: Int {
        map(\.id).max() ?? 0
    }
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
                logger.error("Background refresh failed: \(error, privacy: .public)")
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

    // MARK: Registration & Scheduling
    static func register() {
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let appRefreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(appRefreshTask)
        }
        if registered {
            logger.info("Registered background task: \(self.taskIdentifier, privacy: .public)")
        } else {
            logger.error("Failed to register background task: \(self.taskIdentifier, privacy: .public)")
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
            logger.error("Failed scheduling background refresh: \(error, privacy: .public)")
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
            logger.info("Notification authorization granted? \(granted, privacy: .public)")
        } catch {
            logger.error("Notification auth error: \(error, privacy: .public)")
        }
    }

    // MARK: Fetch & Notify
    static func performFetchAndNotify() async throws {
        guard let session = try await FALoginView.makeSession() else {
            logger.info("No valid FA session for background refresh (user likely logged out)")
            return
        }

        let submissions = try await session.submissionPreviews(from: nil)
        let notes = try await session.notePreviews(from: .inbox)
        let previews = try await session.notificationPreviews()

        var latestNotificationIDs = LatestNotificationIDs.load()

        let newSubmissions = submissions.filter { $0.id > latestNotificationIDs.submissionID }
        let newNotes = notes.filter { $0.unread && $0.id > latestNotificationIDs.noteID }
        let newSubmissionComments = previews.submissionComments.filter {
            $0.id > latestNotificationIDs.submissionCommentID
        }
        let newJournalComments = previews.journalComments.filter { $0.id > latestNotificationIDs.journalCommentID }
        let newShouts = previews.shouts.filter { $0.id > latestNotificationIDs.shoutID }
        let newJournals = previews.journals.filter { $0.id > latestNotificationIDs.journalID }

        // Respect user toggles already used in Settings
        let countSubmissions = Defaults[.notifySubmissions] ? newSubmissions.count : 0
        let countNotes = Defaults[.notifyNotes] ? newNotes.count : 0
        let countSubmissionComments = Defaults[.notifySubmissionComments] ? newSubmissionComments.count : 0
        let countJournalComments = Defaults[.notifyJournalComments] ? newJournalComments.count : 0
        let countShouts = Defaults[.notifyShouts] ? newShouts.count : 0
        let countJournals = Defaults[.notifyJournals] ? newJournals.count : 0

        let totalNew = countSubmissions + countNotes + countSubmissionComments + countJournalComments + countShouts + countJournals
        guard totalNew > 0 else {
            logger.info("Background refresh: no new notifiable item")
            return
        }

        guard await postLocalNotification(
            newSubmissions: countSubmissions,
            newNotes: countNotes,
            newSubmissionComments: countSubmissionComments,
            newJournalComments: countJournalComments,
            newShouts: countShouts,
            newJournals: countJournals
        ) else {
            return
        }

        latestNotificationIDs.merge(LatestNotificationIDs(submissions: submissions, notes: notes, previews: previews))
        latestNotificationIDs.save()
    }

    static func buildNotification(
        newSubmissions: Int,
        newNotes: Int,
        newSubmissionComments: Int,
        newJournalComments: Int,
        newShouts: Int,
        newJournals: Int,
    ) -> UNMutableNotificationContent? {
        var parts: [String] = []
        if newSubmissions > 0 {
            parts.append("\(newSubmissions) submission\(newSubmissions > 1 ? "s" : "")")
        }
        if newNotes > 0 {
            parts.append("\(newNotes) note\(newNotes > 1 ? "s" : "")")
        }
        if newSubmissionComments > 0 {
            parts.append("\(newSubmissionComments) submission comment\(newSubmissionComments > 1 ? "s" : "")")
        }
        if newJournalComments > 0 {
            parts.append("\(newJournalComments) journal comment\(newJournalComments > 1 ? "s" : "")")
        }
        if newShouts > 0 { parts.append("\(newShouts) shout\(newShouts > 1 ? "s" : "")") }
        if newJournals > 0 { parts.append("\(newJournals) journal\(newJournals > 1 ? "s" : "")") }

        guard !parts.isEmpty else { return nil }

        let content = UNMutableNotificationContent()
        content.title = "New activity on Fur Affinity"
        content.body = parts.joined(separator: ", ")
        return content
    }

    private static func postLocalNotification(
        newSubmissions: Int,
        newNotes: Int,
        newSubmissionComments: Int,
        newJournalComments: Int,
        newShouts: Int,
        newJournals: Int
    ) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            logger.info(
                "Skipping local notification because authorization status is \(settings.authorizationStatus.rawValue)"
            )
            return false
        }

        guard let content = buildNotification(
            newSubmissions: newSubmissions,
            newNotes: newNotes,
            newSubmissionComments: newSubmissionComments,
            newJournalComments: newJournalComments,
            newShouts: newShouts,
            newJournals: newJournals
        ) else {
            return false
        }
        
        if settings.soundSetting == .enabled {
            content.sound = .default
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: "fa.background.refresh-\(UUID())", content: content, trigger: trigger)
        do {
            try await center.add(request)
            logger.info("Scheduled local notification for background refresh")
            return true
        } catch {
            logger.error("Failed to schedule local notification: \(error, privacy: .public)")
            return false
        }
    }
}

