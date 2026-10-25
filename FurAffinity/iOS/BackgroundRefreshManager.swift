//
//  BackgroundRefreshManager.swift
//  FurAffinity
//
//  Created by Ceylo on 24/05/2026.
//

#if !FA_SKIP_MODULE

import BackgroundTasks
import FAKit
import UserNotifications

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

// Registers, schedules and handles the BGAppRefresh task that runs
// `performFetchAndNotify`, and enriches its notifications with Intents.
extension BackgroundRefreshManager {
    // Identifier must be added to Info.plist (BGTaskSchedulerPermittedIdentifiers)
    static var taskIdentifier: String { Bundle.main.bundleIdentifier! + ".background-refresh" }

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

    // The feed fetched first is the latest one, so the session's own page serves it.
    static func makeBackgroundSession() async throws -> OnlineFASession? {
        try await FALoginView.makeSession(source: .submissionsFeed(from: nil))
    }

    static func enrich(_ content: UNMutableNotificationContent, for record: PendingNotificationRecord) async -> UNNotificationContent {
        await communicationContent(content, author: record.author)
    }

    /// Sets the submission attachments on a mutable copy of the enriched content:
    /// `updating(from:)` returns immutable content and may drop attachments, so this
    /// is the robust path.
    static func attaching(_ attachments: [UNNotificationAttachment], to content: UNNotificationContent) -> UNNotificationContent {
        guard let mutable = content.mutableCopy() as? UNMutableNotificationContent else {
            return content
        }
        mutable.attachments = attachments
        // The category routes the notification to the content extension that
        // reveals the clear image on expand. Set here (post-enrichment) since
        // updating(from:) can reset it.
        mutable.categoryIdentifier = submissionCategoryIdentifier
        return mutable
    }
}

#endif
