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

    var profile = ActivityProfile()
    var fetchDates: [Date] = []
    var lastForegroundEnd: Date?

    enum Decision: Equatable {
        case fetch
        case skip(nextSlot: Date)
    }

    func decision(now: Date, calendar: Calendar) -> Decision {
        let slots = BackgroundRefreshSlots(profile: profile)
        let lastSeen = (fetchDates + [lastForegroundEnd].compactMap { $0 }).filter { $0 <= now }.max()
        let slotPassed = lastSeen.map { slots.latestSlot(atOrBefore: now, calendar: calendar) > $0 } ?? true
        let recentFetches = fetchDates.filter { $0 > now - Self.window && $0 <= now }.count
        guard slotPassed && recentFetches < BackgroundRefreshSlots.perDay else {
            return .skip(nextSlot: slots.nextSlot(after: now, calendar: calendar))
        }
        return .fetch
    }

    mutating func recordFetch(at date: Date) {
        fetchDates.append(date)
        fetchDates.removeAll { $0 <= date - Self.window }
    }

    func nextRunDate(after now: Date, calendar: Calendar) -> Date {
        let nextSlot = BackgroundRefreshSlots(profile: profile).nextSlot(after: now, calendar: calendar)
        return max(nextSlot, now + Self.minimumRunInterval)
    }
}

extension BackgroundRefreshManager {
    @MainActor
    static func recordAppOpen() {
        Defaults[.backgroundRefreshBudget].profile.recordOpen(at: Date(), calendar: .current)
    }

    @MainActor
    static func recordForegroundEnd() {
        Defaults[.backgroundRefreshBudget].lastForegroundEnd = Date()
    }

    @MainActor
    static func claimBudgetedFetch() -> Date? {
        var budget = Defaults[.backgroundRefreshBudget]
        let now = Date()
        if case .skip(let nextSlot) = budget.decision(now: now, calendar: .current) {
            return nextSlot
        }
        budget.recordFetch(at: now)
        Defaults[.backgroundRefreshBudget] = budget
        return nil
    }
}
