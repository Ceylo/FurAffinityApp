//
//  BackgroundRefreshBudget.swift
//  FurAffinity
//
//  Created by Ceylo on 25/10/2026.
//

import Defaults
import Foundation

struct ActivityProfile: Codable, Equatable {
    static let dailyDecay = 0.93

    var opens = [Double](repeating: 0, count: 24)
    var updated: Date?

    mutating func recordOpen(at date: Date, calendar: Calendar) {
        if let updated {
            let days = date.timeIntervalSince(updated) / 86400
            if days > 0 {
                let decay = pow(Self.dailyDecay, days)
                opens = opens.map { $0 * decay }
            }
        }
        updated = max(updated ?? date, date)
        opens[calendar.component(.hour, from: date)] += 1
    }
}

struct BackgroundRefreshSlots {
    static let perDay = 10
    static let learnedShare = 0.8
    /// Caps an hour at 2 slots, so slots stay at least 30 min apart (a little less on a 23-hour day).
    static let maxHourWeight = 2 / Double(perDay)
    static let prior: [Double] = (0..<24).map { $0 < 8 ? 0.1 : 1 }

    let hourWeights: [Double]

    init(profile: ActivityProfile) {
        let prior = Self.normalized(Self.prior)
        let weights: [Double]
        if profile.opens.reduce(0, +) > 0 {
            let learned = Self.normalized(profile.opens)
            weights = zip(learned, prior).map { Self.learnedShare * $0 + (1 - Self.learnedShare) * $1 }
        } else {
            weights = prior
        }
        hourWeights = Self.capped(weights, at: Self.maxHourWeight)
    }

    func slots(onDayOf date: Date, calendar: Calendar) -> [Date] {
        let dayStart = calendar.startOfDay(for: date)
        let dayLength = calendar.date(byAdding: .day, value: 1, to: dayStart)!.timeIntervalSince(dayStart)
        var slots: [Date] = []
        var cumulative = 0.0
        var hour = 0
        for k in 0..<Self.perDay {
            let target = (Double(k) + 0.5) / Double(Self.perDay)
            while hour < 23 && cumulative + hourWeights[hour] < target {
                cumulative += hourWeights[hour]
                hour += 1
            }
            let fraction = min(max((target - cumulative) / hourWeights[hour], 0), 1)
            slots.append(dayStart.addingTimeInterval((Double(hour) + fraction) / 24 * dayLength))
        }
        return slots
    }

    func latestSlot(atOrBefore date: Date, calendar: Calendar) -> Date {
        slots(around: date, calendar: calendar).last { $0 <= date }!
    }

    func nextSlot(after date: Date, calendar: Calendar) -> Date {
        slots(around: date, calendar: calendar).first { $0 > date }!
    }

    private func slots(around date: Date, calendar: Calendar) -> [Date] {
        let dayStart = calendar.startOfDay(for: date)
        return [-1, 0, 1].flatMap { offset in
            slots(onDayOf: calendar.date(byAdding: .day, value: offset, to: dayStart)!, calendar: calendar)
        }
    }

    private static func normalized(_ values: [Double]) -> [Double] {
        let sum = values.reduce(0, +)
        return values.map { $0 / sum }
    }

    private static func capped(_ weights: [Double], at cap: Double) -> [Double] {
        var weights = weights
        var isCapped = [Bool](repeating: false, count: weights.count)
        while true {
            let over = weights.indices.filter { !isCapped[$0] && weights[$0] > cap }
            guard !over.isEmpty else { return weights }
            var excess = 0.0
            for i in over {
                excess += weights[i] - cap
                weights[i] = cap
                isCapped[i] = true
            }
            let free = weights.indices.filter { !isCapped[$0] }
            let freeSum = free.reduce(0) { $0 + weights[$1] }
            guard freeSum > 0 else { return weights }
            for i in free {
                weights[i] += excess * weights[i] / freeSum
            }
        }
    }
}

struct BackgroundRefreshBudget: Codable, Equatable, Defaults.Serializable {
    static let window: TimeInterval = 24 * 3600
    static let minimumRunInterval: TimeInterval = 30 * 60
    static let retryAllowance = BackgroundRefreshSlots.perDay / 4
    static let quickRetryDelay: TimeInterval = 5 * 60
    /// The average gap between slots: a later retry would be no sooner than the next slot.
    static let maxRetryDelay = window / Double(BackgroundRefreshSlots.perDay)

    var profile = ActivityProfile()
    var fetchDates: [Date] = []
    var lastForegroundEnd: Date?
    var retry: Retry?
    var failures: Failures?

    struct Retry: Codable, Equatable {
        var notBefore: Date
    }

    struct Failures: Codable, Equatable {
        var outcome: Outcome
        var count: Int
    }

    enum Decision: Equatable {
        case fetch
        case skip(nextSlot: Date)
    }

    enum Outcome: String, Codable, Equatable {
        case completed
        case unreachedFA
        /// Stopped after reaching furaffinity.net: the app came back, or the system took the job.
        case interrupted
        case unreachableAfterFA
        case faError
    }

    func decision(now: Date, calendar: Calendar) -> Decision {
        if let retry = usableRetry(at: now) {
            return now >= retry.notBefore ? .fetch : .skip(nextSlot: retry.notBefore)
        }
        let slots = BackgroundRefreshSlots(profile: profile)
        let lastSeen = (fetchDates + [lastForegroundEnd].compactMap { $0 }).filter { $0 <= now }.max()
        let slotPassed = lastSeen.map { slots.latestSlot(atOrBefore: now, calendar: calendar) > $0 } ?? true
        guard slotPassed && recentFetches(at: now) < BackgroundRefreshSlots.perDay else {
            return .skip(nextSlot: slots.nextSlot(after: now, calendar: calendar))
        }
        return .fetch
    }

    mutating func recordFetch(at date: Date) {
        fetchDates.append(date)
        fetchDates.removeAll { $0 <= date - Self.window }
        retry = nil
    }

    mutating func recordOpen(at date: Date, calendar: Calendar) {
        profile.recordOpen(at: date, calendar: calendar)
        retry = nil
        failures = nil
    }

    mutating func recordForegroundEnd(at date: Date) {
        lastForegroundEnd = date
        retry = nil
        failures = nil
    }

    mutating func settle(_ outcome: Outcome, claimedAt: Date, now: Date) {
        func owe(after delay: TimeInterval) {
            let count = failures.flatMap { $0.outcome == outcome ? $0.count + 1 : nil } ?? 1
            failures = Failures(outcome: outcome, count: count)
            let backedOff = delay * pow(2, Double(count - 1))
            retry = backedOff <= Self.maxRetryDelay ? Retry(notBefore: now + backedOff) : nil
        }
        switch outcome {
        case .completed:
            retry = nil
            failures = nil
        case .unreachedFA:
            fetchDates.removeAll { $0 == claimedAt }
            owe(after: Self.quickRetryDelay)
        case .interrupted:
            owe(after: 0)
        case .unreachableAfterFA:
            owe(after: Self.quickRetryDelay)
        case .faError:
            owe(after: Self.minimumRunInterval)
        }
    }

    func nextRunDate(after now: Date, calendar: Calendar) -> Date {
        if let retry = usableRetry(at: now) {
            return max(retry.notBefore, now + Self.quickRetryDelay)
        }
        let nextSlot = BackgroundRefreshSlots(profile: profile).nextSlot(after: now, calendar: calendar)
        return max(nextSlot, now + Self.minimumRunInterval)
    }

    private func usableRetry(at now: Date) -> Retry? {
        guard let retry else {
            return nil
        }
        let isPaid = failures?.outcome != .unreachedFA
        let cap = BackgroundRefreshSlots.perDay + (isPaid ? Self.retryAllowance : 0)
        return recentFetches(at: now) < cap ? retry : nil
    }

    private func recentFetches(at now: Date) -> Int {
        fetchDates.filter { $0 > now - Self.window && $0 <= now }.count
    }
}

extension BackgroundRefreshManager {
    @MainActor
    static func recordAppOpen() {
        Defaults[.backgroundRefreshBudget].recordOpen(at: Date(), calendar: .current)
    }

    @MainActor
    static func recordForegroundEnd() {
        Defaults[.backgroundRefreshBudget].recordForegroundEnd(at: Date())
    }

    enum BudgetClaim: Equatable {
        case granted(at: Date)
        case denied(nextSlot: Date)
    }

    @MainActor
    static func claimBudgetedFetch() -> BudgetClaim {
        var budget = Defaults[.backgroundRefreshBudget]
        let now = Date()
        if case .skip(let nextSlot) = budget.decision(now: now, calendar: .current) {
            return .denied(nextSlot: nextSlot)
        }
        budget.recordFetch(at: now)
        Defaults[.backgroundRefreshBudget] = budget
        return .granted(at: now)
    }

    @MainActor
    static func settleBudgetedFetch(_ outcome: BackgroundRefreshBudget.Outcome, claimedAt: Date?) {
        guard let claimedAt else { return }
        logger.info("Background refresh outcome: \(outcome)")
        Defaults[.backgroundRefreshBudget].settle(outcome, claimedAt: claimedAt, now: Date())
    }
}
