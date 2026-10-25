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
    /// Caps an hour at 2 slots, so slots stay at least 30 min apart.
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
            let hourStart = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: dayStart) ?? dayStart
            slots.append(hourStart.addingTimeInterval(fraction * 3600))
        }
        return slots.sorted()
    }

    func latestSlot(atOrBefore date: Date, calendar: Calendar) -> Date {
        if let slot = slots(onDayOf: date, calendar: calendar).last(where: { $0 <= date }) {
            return slot
        }
        let previousDay = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date))!
        return slots(onDayOf: previousDay, calendar: calendar).last!
    }

    func nextSlot(after date: Date, calendar: Calendar) -> Date {
        if let slot = slots(onDayOf: date, calendar: calendar).first(where: { $0 > date }) {
            return slot
        }
        let nextDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date))!
        return slots(onDayOf: nextDay, calendar: calendar).first!
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
        let lastSeen = [fetchDates.max(), lastForegroundEnd].compactMap { $0 }.max()
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

    mutating func recordForegroundEnd(at date: Date) {
        lastForegroundEnd = date
    }

    func nextRunDate(after now: Date, calendar: Calendar) -> Date {
        let nextSlot = BackgroundRefreshSlots(profile: profile).nextSlot(after: now, calendar: calendar)
        return max(nextSlot, now + Self.minimumRunInterval)
    }
}
