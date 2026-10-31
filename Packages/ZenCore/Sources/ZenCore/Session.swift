import Foundation

// MARK: - Session rule

/// What counts as one scrolling session, and when it nudges.
///
/// iOS never tells an app when another app opens or closes. Screen Time only reports
/// "this app has now been used for N minutes since time T". So a session is detected like this:
///
/// 1. **Armed:** wait for the first minute of use of the app.
/// 2. **Watching:** a window starts right then. If the user reaches the session limit
///    (e.g. 10 minutes in a row) before the window ends, they get nudged. The window is
///    `limit + breakAllowance` minutes long (at least 15, the shortest interval iOS allows),
///    so a short break (checking a message) doesn't end the session, but a real break does.
/// 3. If they keep scrolling after the nudge, a new window starts and they're nudged again
///    every `limit` minutes. When a window ends without reaching the limit, the session is over
///    and we go back to step 1.
public enum SessionRule {
    /// Session limits the user can choose, in minutes.
    public static let limitRange = 5...60
    public static let defaultLimit = 10
    /// Minutes of non-use a session tolerates before it counts as over.
    public static let breakAllowance = 5
    /// `DeviceActivitySchedule` rejects intervals shorter than 15 minutes.
    public static let minimumWindow = 15
    /// Minutes of use that start a session.
    public static let startThreshold = 1
    /// How long the "armed" state waits for a session to start before it is re-armed.
    public static let armedWindow = 24 * 60

    public static func clamped(_ limit: Int) -> Int {
        min(max(limit, limitRange.lowerBound), limitRange.upperBound)
    }

    /// Length of a watching window for a given session limit.
    public static func window(limit: Int) -> Int {
        max(minimumWindow, clamped(limit) + breakAllowance)
    }
}

// MARK: - Session plan

/// One Screen Time monitoring interval for one tracked app.
public struct SessionWindow: Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        /// Waiting for the first minute of use.
        case armed
        /// A session is going on; waiting for it to reach the limit.
        case watching
    }

    public var phase: Phase
    /// How long the interval lasts, in minutes.
    public var length: Int
    /// Minutes of use within the interval that fire its event.
    public var threshold: Int

    public init(phase: Phase, length: Int, threshold: Int) {
        self.phase = phase
        self.length = length
        self.threshold = threshold
    }

    public static let armed = SessionWindow(phase: .armed, length: SessionRule.armedWindow, threshold: SessionRule.startThreshold)

    /// The window to watch next, given how many minutes of the session were already used.
    /// The first window after a session starts waits for `limit - startThreshold` more minutes;
    /// after a nudge the next window waits for another full `limit`.
    public static func watching(limit: Int, sessionMinutes: Int) -> SessionWindow {
        let limit = SessionRule.clamped(limit)
        let toNextNudge = limit - (sessionMinutes % limit)
        return SessionWindow(phase: .watching, length: SessionRule.window(limit: limit), threshold: max(1, toNextNudge))
    }

    /// Event name for this window's threshold: `"<phase>.<minutes>"`, e.g. `"watching.9"`.
    public var eventName: String { "\(phase.rawValue).\(threshold)" }

    public static func parseEvent(_ raw: String) -> (phase: Phase, minutes: Int)? {
        let parts = raw.split(separator: ".")
        guard parts.count == 2,
              let phase = Phase(rawValue: String(parts[0])),
              let minutes = Int(parts[1]), minutes > 0 else { return nil }
        return (phase, minutes)
    }
}

/// Activity names: one per tracked app (`"zen.session.<appID>"`), plus the daily usage activity.
public enum SessionActivity {
    public static let prefix = "zen.session."

    public static func name(appID: String) -> String { prefix + appID }

    public static func appID(from activity: String) -> String? {
        guard activity.hasPrefix(prefix) else { return nil }
        let id = String(activity.dropFirst(prefix.count))
        return id.isEmpty ? nil : id
    }

    /// iOS monitors at most 20 activities at once; one is the daily usage activity.
    public static let maxTrackedApps = 19
}

// MARK: - Session state (shared between the app and the extension)

/// Where each app's session stands. Written by whoever (re)schedules a window.
public struct SessionState: Codable, Equatable, Sendable {
    public var phase: SessionWindow.Phase
    /// Minutes of use in the current session (0 while armed).
    public var minutes: Int
    /// When the current window ends. `intervalDidEnd` before this is a restart, not a real end.
    public var windowEnds: Date

    public init(phase: SessionWindow.Phase, minutes: Int, windowEnds: Date) {
        self.phase = phase
        self.minutes = minutes
        self.windowEnds = windowEnds
    }
}

extension SharedStore {
    /// Allowed early arrival for `intervalDidEnd`, which iOS doesn't deliver to the second.
    static let endTolerance: TimeInterval = 60

    public func sessionState(appID: String) -> SessionState? {
        sessions[appID]
    }

    /// Records that a window was (re)started for `appID`.
    public func setWindow(_ window: SessionWindow, appID: String, sessionMinutes: Int, now: Date = Date()) {
        var all = sessions
        all[appID] = SessionState(phase: window.phase, minutes: sessionMinutes, windowEnds: now.addingTimeInterval(TimeInterval(window.length * 60)))
        sessions = all
    }

    public func clearSession(appID: String) {
        var all = sessions
        all[appID] = nil
        sessions = all
    }

    /// Whether an `intervalDidEnd` for `appID` is the real end of its current window
    /// (rather than the echo of a window we just replaced).
    public func windowHasEnded(appID: String, now: Date = Date()) -> Bool {
        guard let state = sessions[appID] else { return true }
        return now >= state.windowEnds.addingTimeInterval(-Self.endTolerance)
    }

    /// Handles a session event for `appID`. Returns the window to schedule next, and the app to
    /// nudge about (with `minutes` set to the session length so far) when the limit was reached.
    public func handleSessionEvent(appID: String, phase: SessionWindow.Phase, minutes: Int, now: Date = Date()) -> (next: SessionWindow, nudge: TrackedApp?)? {
        guard var app = apps.first(where: { $0.id == appID }) else { return nil }
        let limit = SessionRule.clamped(app.limit)
        let previous = phase == .watching ? (sessions[appID]?.minutes ?? 0) : 0
        let total = previous + minutes
        let next = SessionWindow.watching(limit: limit, sessionMinutes: total)
        setWindow(next, appID: appID, sessionMinutes: total, now: now)

        guard phase == .watching, total >= limit else { return (next, nil) }
        app.minutes = total
        recordSessionNudge(appID: appID, minutes: total, now: now)
        return (next, app)
    }

    /// Records the end of a session and returns the window that waits for the next one.
    @discardableResult
    public func endSession(appID: String, now: Date = Date()) -> SessionWindow {
        setWindow(.armed, appID: appID, sessionMinutes: 0, now: now)
        return .armed
    }

    /// The longest session that triggered a nudge today, per app.
    public func longestSessions(now: Date = Date()) -> [String: Int] {
        usage(now: now).longestSession
    }

    private func recordSessionNudge(appID: String, minutes: Int, now: Date) {
        var u = usage(now: now)
        u.longestSession[appID] = max(u.longestSession[appID] ?? 0, minutes)
        u.nudges[appID, default: 0] += 1
        saveUsage(u)
    }
}
