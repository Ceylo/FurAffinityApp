//
//  BackgroundRefreshBudgetTests.swift
//  FurAffinityTests
//
//  Created by Ceylo on 25/10/2026.
//

import Foundation
import Testing
#if FA_SKIP_MODULE
@testable import FurAffinityUI
#else
@testable import Fur_Affinity
#endif

struct BackgroundRefreshBudgetTests {
    // MARK: - Helpers
    static func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    let calendar = Self.calendar("Europe/Paris")
    let minimumGap: TimeInterval = 30 * 60 - 1

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    var day: Date { date(2026, 6, 10) }

    func profile(_ opens: [Int: Double]) -> ActivityProfile {
        var profile = ActivityProfile()
        for (hour, count) in opens {
            profile.opens[hour] = count
        }
        return profile
    }

    var flatProfile: ActivityProfile { profile(Dictionary(uniqueKeysWithValues: (0..<24).map { ($0, 1) })) }
    var eveningProfile: ActivityProfile { profile(Dictionary(uniqueKeysWithValues: (18..<24).map { ($0, 10) })) }
    var morningProfile: ActivityProfile { profile(Dictionary(uniqueKeysWithValues: (6..<12).map { ($0, 10) })) }

    func slots(_ profile: ActivityProfile = ActivityProfile(), on day: Date? = nil) -> [Date] {
        BackgroundRefreshSlots(profile: profile).slots(onDayOf: day ?? self.day, calendar: calendar)
    }

    func hour(_ date: Date) -> Int {
        calendar.component(.hour, from: date)
    }

    func gaps(_ dates: [Date]) -> [TimeInterval] {
        zip(dates.dropFirst(), dates).map { $0.timeIntervalSince($1) }
    }

    func walk(
        _ budget: inout BackgroundRefreshBudget,
        from start: Date,
        to end: Date,
        calendar: (Date) -> Calendar,
        beforeEachRun: (Date, inout BackgroundRefreshBudget) -> Void = { _, _ in }
    ) -> [Date] {
        var fetches: [Date] = []
        var now = start
        while now < end {
            beforeEachRun(now, &budget)
            if budget.decision(now: now, calendar: calendar(now)) == .fetch {
                budget.recordFetch(at: now)
                fetches.append(now)
            }
            now += 15 * 60
        }
        return fetches
    }

    func maxFetchesInAnyDay(_ fetches: [Date]) -> Int {
        fetches.map { end in fetches.filter { $0 > end - 24 * 3600 && $0 <= end }.count }.max() ?? 0
    }

    struct SplitMix64: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    // MARK: - Slots
    @Test func slots_areTenAscendingOnTheirDay() {
        let profiles = [
            ActivityProfile(),
            flatProfile,
            profile([20: 50]),
            profile(Dictionary(uniqueKeysWithValues: (0..<8).map { ($0, 5) })),
        ]
        let days = [day, date(2026, 3, 29), date(2026, 10, 25)]
        for profile in profiles {
            for day in days {
                let slots = slots(profile, on: day)
                #expect(slots.count == 10)
                #expect(slots == slots.sorted())
                #expect(slots.allSatisfy { calendar.isDate($0, inSameDayAs: day) })
            }
        }
    }

    @Test func noHistory_spreadsSlotsEvenlyOverDaytime() throws {
        let slots = slots()
        #expect(slots.allSatisfy { hour($0) >= 8 })
        let gaps = gaps(slots)
        let mean = gaps.reduce(0, +) / Double(gaps.count)
        #expect(gaps.allSatisfy { abs($0 - mean) < mean * 0.05 })
    }

    @Test func eveningProfile_keepsAMorningSlot() {
        let slots = slots(eveningProfile)
        #expect(slots.filter { hour($0) >= 18 }.count >= 6)
        #expect(slots.contains { hour($0) < 12 })
    }

    @Test func singleHourProfile_keepsSlotsThirtyMinutesApart() {
        let slots = slots(profile([20: 1000]))
        #expect(slots.filter { hour($0) == 20 }.count == 2)
        #expect(gaps(slots).allSatisfy { $0 >= minimumGap })
    }

    @Test func randomProfiles_keepSlotsThirtyMinutesApart() {
        var generator = SplitMix64(state: 42)
        let nextDay = date(2026, 6, 11)
        for _ in 0..<200 {
            var profile = ActivityProfile()
            profile.opens = (0..<24).map { _ in
                Bool.random(using: &generator) ? 0 : Double.random(in: 0..<100, using: &generator)
            }
            let slots = slots(profile) + [slots(profile, on: nextDay)[0]]
            #expect(gaps(slots).allSatisfy { $0 >= minimumGap }, "\(profile.opens)")
        }
    }

    // MARK: - Consumption
    @Test func dayWalk_fetchesOncePerSlot() {
        var budget = BackgroundRefreshBudget()
        budget.lastForegroundEnd = day
        let slots = slots()
        let fetches = walk(&budget, from: day, to: date(2026, 6, 11), calendar: { _ in calendar })
        #expect(fetches.count == 10)
        for (fetch, slot) in zip(fetches, slots) {
            #expect(fetch >= slot && fetch < slot + 15 * 60)
        }
    }

    @Test func lateRun_fetchesOnceThenWaitsForTheNextSlot() {
        let slots = slots()
        var budget = BackgroundRefreshBudget()
        budget.recordFetch(at: slots[0])
        let late = slots[4] + 10 * 60
        #expect(late.timeIntervalSince(slots[1]) >= 3 * 3600)
        #expect(budget.decision(now: late, calendar: calendar) == .fetch)
        budget.recordFetch(at: late)
        #expect(budget.decision(now: late + 15 * 60, calendar: calendar) == .skip(nextSlot: slots[5]))
    }

    @Test func slotDuringForeground_isNotUsed() {
        let slots = slots()
        var budget = BackgroundRefreshBudget()
        budget.recordFetch(at: slots[2])
        budget.lastForegroundEnd = slots[3] + 10 * 60
        #expect(budget.decision(now: slots[3] + 15 * 60, calendar: calendar) == .skip(nextSlot: slots[4]))
        #expect(budget.decision(now: slots[4], calendar: calendar) == .fetch)
    }

    @Test func timeZoneChange_neverExceedsTenFetchesPerDay() {
        let losAngeles = Self.calendar("America/Los_Angeles")
        let switchDate = date(2026, 6, 11, 12)
        var budget = BackgroundRefreshBudget()
        budget.lastForegroundEnd = day
        let fetches = walk(&budget, from: day, to: date(2026, 6, 13), calendar: { $0 < switchDate ? calendar : losAngeles })
        #expect(maxFetchesInAnyDay(fetches) == 10)
    }

    @Test func profileShift_neverExceedsTenFetchesPerDay() {
        let shiftDate = date(2026, 6, 10, 14)
        var budget = BackgroundRefreshBudget(profile: morningProfile)
        budget.lastForegroundEnd = day
        let fetches = walk(&budget, from: day, to: date(2026, 6, 12), calendar: { _ in calendar }) { now, budget in
            if now == shiftDate {
                budget.profile = eveningProfile
            }
        }
        #expect(maxFetchesInAnyDay(fetches) == 10)
    }

    @Test func recordFetch_dropsDatesOlderThanADay() {
        var budget = BackgroundRefreshBudget()
        budget.recordFetch(at: day)
        budget.recordFetch(at: day + 12 * 3600)
        budget.recordFetch(at: day + 24 * 3600)
        #expect(budget.fetchDates == [day + 12 * 3600, day + 24 * 3600])
    }

    // MARK: - Next run date
    @Test func nextRunDate_isAtLeastThirtyMinutesAway() {
        let now = slots()[3] - 5 * 60
        #expect(BackgroundRefreshBudget().nextRunDate(after: now, calendar: calendar) == now + 30 * 60)
    }

    @Test func nextRunDate_returnsTheNextSlot() {
        let slots = slots()
        #expect(BackgroundRefreshBudget().nextRunDate(after: slots[3] + 60, calendar: calendar) == slots[4])
    }

    @Test func nextRunDate_rollsOverToTomorrow() {
        let now = slots()[9] + 60
        let tomorrow = slots(on: date(2026, 6, 11))[0]
        #expect(BackgroundRefreshBudget().nextRunDate(after: now, calendar: calendar) == tomorrow)
    }

    // MARK: - Profile
    @Test func recordOpen_decaysByDailyFactor() {
        var profile = ActivityProfile()
        profile.recordOpen(at: date(2026, 6, 10, 10), calendar: calendar)
        profile.recordOpen(at: date(2026, 6, 15, 11), calendar: calendar)
        let expected = pow(0.93, 5 + 1 / 24.0)
        #expect(abs(profile.opens[10] - expected) < 1e-9)
        #expect(profile.opens[11] == 1)
    }

    @Test func recordOpen_usesTheLocalHourAcrossDSTChanges() {
        func bucket(utc: String) -> Int? {
            var profile = ActivityProfile()
            profile.recordOpen(at: ISO8601DateFormatter().date(from: utc)!, calendar: calendar)
            return profile.opens.firstIndex(of: 1)
        }
        #expect(bucket(utc: "2026-03-29T00:30:00Z") == 1)
        #expect(bucket(utc: "2026-03-29T01:30:00Z") == 3)
        #expect(bucket(utc: "2026-10-25T00:30:00Z") == 2)
        #expect(bucket(utc: "2026-10-25T01:30:00Z") == 2)
        #expect(bucket(utc: "2026-10-25T02:30:00Z") == 3)
    }

    @Test func budget_survivesACodableRoundTrip() throws {
        var budget = BackgroundRefreshBudget()
        budget.profile.recordOpen(at: date(2026, 6, 10, 9, 17), calendar: calendar)
        budget.profile.recordOpen(at: date(2026, 6, 10, 21, 3), calendar: calendar)
        budget.recordFetch(at: date(2026, 6, 10, 12, 41))
        budget.lastForegroundEnd = date(2026, 6, 10, 21, 30)
        let decoded = try JSONDecoder().decode(BackgroundRefreshBudget.self, from: JSONEncoder().encode(budget))
        #expect(decoded == budget)
    }
}
