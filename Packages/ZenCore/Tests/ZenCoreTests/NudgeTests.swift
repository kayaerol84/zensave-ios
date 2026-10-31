import Foundation
import XCTest
@testable import ZenCore

// Ported from src/test/nudge.test.ts, plus tests for the shared store.

final class NudgeRuleTests: XCTestCase {
    func testFiresOnlyWhenTimeReachesTheLimit() {
        XCTAssertFalse(Nudge.shouldNudge(minutes: 19, limit: 20))
        XCTAssertTrue(Nudge.shouldNudge(minutes: 20, limit: 20))
        XCTAssertFalse(Nudge.shouldNudge(minutes: 50, limit: 0))
    }

    func testNamesTheAppTimeAndAlternatives() {
        let msg = Nudge.message(appName: "Instagram", minutes: 25, alternatives: [
            Alternative(id: "a", name: "Imprint", emoji: "", enabled: true),
            Alternative(id: "b", name: "the gym", emoji: "", enabled: true),
        ])
        XCTAssertEqual(msg, "You spent 25 min in Instagram and it is time to switch to Imprint or the gym.")
    }

    func testJoinsThreeAlternativesAndFallsBackWhenNone() {
        let three = [
            Alternative(id: "a", name: "Imprint", emoji: "", enabled: true),
            Alternative(id: "b", name: "the gym", emoji: "", enabled: true),
            Alternative(id: "c", name: "a walk", emoji: "", enabled: true),
        ]
        XCTAssertEqual(Nudge.joinedTargets(three), "Imprint, the gym or a walk")
        XCTAssertEqual(Nudge.joinedTargets([]), "something offline")
    }

    func testFormatsMinutes() {
        XCTAssertEqual(Nudge.formatMinutes(45), "45 min")
        XCTAssertEqual(Nudge.formatMinutes(60), "1h")
        XCTAssertEqual(Nudge.formatMinutes(95), "1h 35m")
    }
}

final class WeeklySummaryTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000_000)
    let day: TimeInterval = 86_400

    func testOnlyCountsChoicesFromTheLast7Days() {
        let s = Nudge.weeklySummary([
            Choice(at: now - day, app: "Instagram", choice: "the gym"),
            Choice(at: now - 8 * day, app: "Instagram", choice: "the gym"),
        ], now: now)
        XCTAssertEqual(s.total, 1)
    }

    func testRanksTheMostChosenActivityFirst() {
        let s = Nudge.weeklySummary([
            Choice(at: now, app: "X", choice: "Imprint"),
            Choice(at: now, app: "X", choice: "the gym"),
            Choice(at: now, app: "TikTok", choice: "the gym"),
        ], now: now)
        XCTAssertEqual(s.byChoice.first, WeeklySummary.Count(choice: "the gym", count: 2))
    }

    func testSwitchesExcludeKeptScrolling() {
        let s = Nudge.weeklySummary([
            Choice(at: now, app: "X", choice: "Imprint"),
            Choice(at: now, app: "X", choice: Nudge.keptScrolling),
        ], now: now)
        XCTAssertEqual(s.switches, 1)
        XCTAssertEqual(s.total, 2)
    }
}

final class HabitTrackerTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_000_000_000)
    let day: TimeInterval = 86_400

    func testDerivesSwitchedDaysIgnoringKeptScrollingAndOldEntries() {
        let days = Habit.autoSwitchedDays([
            Choice(at: now - day, app: "Instagram", choice: "the gym"),
            Choice(at: now - day, app: "Instagram", choice: "kept scrolling"),
            Choice(at: now - 2 * day, app: "X", choice: "kept scrolling"),
            Choice(at: now - 50 * day, app: "X", choice: "Imprint"),
        ], now: now)
        XCTAssertEqual(days, [Habit.dayKey(now - day)])
    }

    func testManualMarkOverridesDerivedValue() {
        let today = Habit.dayKey(now)
        let yesterday = Habit.dayKey(now - day)
        XCTAssertFalse(Habit.isSwitched(today, auto: [today], overrides: [today: false]))
        XCTAssertTrue(Habit.isSwitched(yesterday, auto: [], overrides: [yesterday: true]))
        XCTAssertFalse(Habit.isSwitched(yesterday, auto: [], overrides: [:]))
    }

    func testCountsStreakEndingTodayAndLast30() {
        let auto: Set = [Habit.dayKey(now), Habit.dayKey(now - day)]
        XCTAssertEqual(Habit.progress(auto: auto, overrides: [:], now: now), HabitProgress(streak: 2, last30: 2))
        let overrides = [Habit.dayKey(now - 5 * day): true]
        XCTAssertEqual(Habit.progress(auto: auto, overrides: overrides, now: now), HabitProgress(streak: 2, last30: 3))
    }

    func testBuildsSixWeekGridEndingToday() {
        let grid = Habit.grid(now: now)
        XCTAssertEqual(grid.count, 42)
        XCTAssertEqual(grid.last!, Habit.dayKey(now))
        XCTAssertLessThan(grid.filter { $0 == nil }.count, 7)
    }

    func testGridStartsOnMonday() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Amsterdam")!
        // Wednesday 2026-10-28 → two leading blanks (Mon, Tue).
        let wed = cal.date(from: DateComponents(year: 2026, month: 10, day: 28, hour: 9))!
        let grid = Habit.grid(now: wed, calendar: cal)
        XCTAssertEqual(grid.prefix(3).map { $0 == nil }, [true, true, false])
        XCTAssertEqual(grid.last!, "2026-10-28")
    }
}

final class SharedStoreTests: XCTestCase {
    private func makeStore() -> SharedStore {
        let suite = "zencore.tests.\(UUID().uuidString)"
        return SharedStore(defaults: UserDefaults(suiteName: suite)!)
    }

    func testNudgesOncePerDayWhenUsageReachesLimit() {
        let store = makeStore()
        store.apps = [TrackedApp(id: "ig", name: "Instagram", emoji: "📸", limit: 20)]
        let now = Date(timeIntervalSince1970: 1_000_000_000)

        XCTAssertNil(store.reportUsage(appID: "ig", minutes: 15, now: now))
        let fired = store.reportUsage(appID: "ig", minutes: 20, now: now)
        XCTAssertEqual(fired?.name, "Instagram")
        XCTAssertEqual(fired?.minutes, 20)
        XCTAssertNil(store.reportUsage(appID: "ig", minutes: 25, now: now), "only one nudge per app per day")

        let tomorrow = now.addingTimeInterval(86_400)
        XCTAssertEqual(store.usage(now: tomorrow).minutes, [:], "usage resets on a new day")
        XCTAssertNotNil(store.reportUsage(appID: "ig", minutes: 20, now: tomorrow))
    }

    func testUsageNeverGoesDownWithinADay() {
        let store = makeStore()
        let now = Date()
        store.reportUsage(appID: "ig", minutes: 10, now: now)
        store.reportUsage(appID: "ig", minutes: 5, now: now)
        XCTAssertEqual(store.usage(now: now).minutes["ig"], 10)
    }

    func testRecordsChoices() {
        let store = makeStore()
        store.recordChoice("the gym", app: "Instagram")
        XCTAssertEqual(store.choices.map(\.choice), ["the gym"])
    }
}

final class ScreenTimeEventTests: XCTestCase {
    func testRoundTripsEventNames() {
        let raw = ScreenTimeEvent.name(appID: "ig", minutes: 20)
        XCTAssertEqual(raw, "ig.20")
        XCTAssertEqual(ScreenTimeEvent.parse(raw)?.appID, "ig")
        XCTAssertEqual(ScreenTimeEvent.parse(raw)?.minutes, 20)
        XCTAssertEqual(ScreenTimeEvent.parse("custom.app.id.15")?.appID, "custom.app.id")
        XCTAssertNil(ScreenTimeEvent.parse("nonsense"))
        XCTAssertNil(ScreenTimeEvent.parse(".5"))
    }

    func testThresholdsEndExactlyAtTheLimit() {
        XCTAssertEqual(ScreenTimeEvent.thresholds(limit: 20), [5, 10, 15, 20])
        XCTAssertEqual(ScreenTimeEvent.thresholds(limit: 12), [5, 10, 12])
        XCTAssertEqual(ScreenTimeEvent.thresholds(limit: 5), [5])
        XCTAssertEqual(ScreenTimeEvent.thresholds(limit: 0), [])
    }
}
