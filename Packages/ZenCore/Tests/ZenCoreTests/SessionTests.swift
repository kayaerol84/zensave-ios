import Foundation
import XCTest
@testable import ZenCore

final class SessionRuleTests: XCTestCase {
    func testWindowAllowsAShortBreakButIsAtLeast15Minutes() {
        XCTAssertEqual(SessionRule.window(limit: 5), 15)
        XCTAssertEqual(SessionRule.window(limit: 10), 15)
        XCTAssertEqual(SessionRule.window(limit: 20), 25)
        XCTAssertEqual(SessionRule.window(limit: 60), 65)
    }

    func testLimitsAreClampedToTheAllowedRange() {
        XCTAssertEqual(SessionRule.clamped(0), 5)
        XCTAssertEqual(SessionRule.clamped(10), 10)
        XCTAssertEqual(SessionRule.clamped(120), 60)
    }

    func testFirstWatchWaitsForTheRestOfTheLimitThenAFullLimit() {
        XCTAssertEqual(SessionWindow.watching(limit: 10, sessionMinutes: 1),
                       SessionWindow(phase: .watching, length: 15, threshold: 9))
        XCTAssertEqual(SessionWindow.watching(limit: 10, sessionMinutes: 10).threshold, 10)
        XCTAssertEqual(SessionWindow.watching(limit: 10, sessionMinutes: 20).threshold, 10)
    }

    func testEventNamesRoundTrip() {
        let armed = SessionWindow.armed
        XCTAssertEqual(armed.eventName, "armed.1")
        XCTAssertEqual(SessionWindow.parseEvent(armed.eventName)?.phase, .armed)
        let parsed = SessionWindow.parseEvent("watching.9")
        XCTAssertEqual(parsed?.phase, .watching)
        XCTAssertEqual(parsed?.minutes, 9)
        XCTAssertNil(SessionWindow.parseEvent("ig.20"))
        XCTAssertNil(SessionWindow.parseEvent("watching.0"))
        XCTAssertNil(SessionWindow.parseEvent("watching"))
    }

    func testActivityNamesRoundTrip() {
        XCTAssertEqual(SessionActivity.name(appID: "ig"), "zen.session.ig")
        XCTAssertEqual(SessionActivity.appID(from: "zen.session.ig"), "ig")
        XCTAssertNil(SessionActivity.appID(from: "zen.daily"))
        XCTAssertNil(SessionActivity.appID(from: "zen.session."))
    }
}

final class SessionFlowTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_000_000_000)

    private func makeStore(limit: Int = 10) -> SharedStore {
        let store = SharedStore(defaults: UserDefaults(suiteName: "zencore.session.\(UUID().uuidString)")!)
        store.apps = [TrackedApp(id: "ig", name: "Instagram", emoji: "📸", limit: limit)]
        return store
    }

    func testNudgesAfterTenMinutesInARowAndAgainEveryTenMore() {
        let store = makeStore()
        store.endSession(appID: "ig", now: t0)

        // First minute of use: a session starts, watch for 9 more within 15 minutes.
        let start = store.handleSessionEvent(appID: "ig", phase: .armed, minutes: 1, now: t0.addingTimeInterval(60))
        XCTAssertNil(start?.nudge)
        XCTAssertEqual(start?.next, SessionWindow(phase: .watching, length: 15, threshold: 9))

        // 9 more minutes: 10 in a row → nudge.
        let first = store.handleSessionEvent(appID: "ig", phase: .watching, minutes: 9, now: t0.addingTimeInterval(600))
        XCTAssertEqual(first?.nudge?.name, "Instagram")
        XCTAssertEqual(first?.nudge?.minutes, 10)
        XCTAssertEqual(first?.next.threshold, 10)

        // Kept scrolling: nudged again at 20.
        let second = store.handleSessionEvent(appID: "ig", phase: .watching, minutes: 10, now: t0.addingTimeInterval(1200))
        XCTAssertEqual(second?.nudge?.minutes, 20)

        let usage = store.usage(now: t0.addingTimeInterval(1200))
        XCTAssertEqual(usage.longestSession["ig"], 20)
        XCTAssertEqual(usage.nudges["ig"], 2)
    }

    func testABreakEndsTheSessionAndTheCountStartsOver() {
        let store = makeStore()
        store.endSession(appID: "ig", now: t0)
        _ = store.handleSessionEvent(appID: "ig", phase: .armed, minutes: 1, now: t0)

        // The watching window ran out (15 min) before reaching the limit.
        let end = t0.addingTimeInterval(15 * 60)
        XCTAssertTrue(store.windowHasEnded(appID: "ig", now: end))
        XCTAssertEqual(store.endSession(appID: "ig", now: end), .armed)
        XCTAssertEqual(store.sessionState(appID: "ig")?.minutes, 0)

        // A new session needs the full 10 minutes again.
        let restart = store.handleSessionEvent(appID: "ig", phase: .armed, minutes: 1, now: end.addingTimeInterval(60))
        XCTAssertEqual(restart?.next.threshold, 9)
        let reached = store.handleSessionEvent(appID: "ig", phase: .watching, minutes: 9, now: end.addingTimeInterval(600))
        XCTAssertEqual(reached?.nudge?.minutes, 10)
    }

    func testEndOfAReplacedWindowIsIgnored() {
        let store = makeStore()
        store.endSession(appID: "ig", now: t0)
        _ = store.handleSessionEvent(appID: "ig", phase: .armed, minutes: 1, now: t0)
        // The replaced armed window's intervalDidEnd arrives right after the new window started.
        XCTAssertFalse(store.windowHasEnded(appID: "ig", now: t0.addingTimeInterval(1)))
    }

    func testUsesTheConfiguredLimit() {
        let store = makeStore(limit: 25)
        store.endSession(appID: "ig", now: t0)
        let start = store.handleSessionEvent(appID: "ig", phase: .armed, minutes: 1, now: t0)
        XCTAssertEqual(start?.next, SessionWindow(phase: .watching, length: 30, threshold: 24))
        let early = store.handleSessionEvent(appID: "ig", phase: .watching, minutes: 9, now: t0)
        XCTAssertNil(early?.nudge, "10 minutes is not enough when the limit is 25")
    }

    func testIgnoresUnknownApps() {
        let store = makeStore()
        XCTAssertNil(store.handleSessionEvent(appID: "nope", phase: .armed, minutes: 1, now: t0))
    }
}
