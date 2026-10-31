import Foundation

/// What the user told the coach about themselves (the "Goals" tab).
public struct CoachProfile: Codable, Hashable, Sendable {
    public var goals: String
    public var availableTime: String
    public var activities: String
    public var useAI: Bool

    public init(goals: String = "", availableTime: String = "", activities: String = "", useAI: Bool = true) {
        self.goals = goals
        self.availableTime = availableTime
        self.activities = activities
        self.useAI = useAI
    }

    public var isEmpty: Bool {
        goals.isEmpty && availableTime.isEmpty && activities.isEmpty
    }
}

/// Minutes used per tracked app on one calendar day, written by the Screen Time monitor
/// extension and read by the app. Resets when the day changes.
public struct DailyUsage: Codable, Equatable, Sendable {
    public var day: String
    /// Total minutes used today (in `ScreenTimeEvent` steps).
    public var minutes: [String: Int]
    /// Longest session that triggered a nudge today.
    public var longestSession: [String: Int]
    /// Session nudges sent today.
    public var nudges: [String: Int]

    public init(day: String, minutes: [String: Int] = [:], longestSession: [String: Int] = [:], nudges: [String: Int] = [:]) {
        self.day = day
        self.minutes = minutes
        self.longestSession = longestSession
        self.nudges = nudges
    }

    // Tolerates blobs written by older versions, which lack some keys.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        minutes = try c.decodeIfPresent([String: Int].self, forKey: .minutes) ?? [:]
        longestSession = try c.decodeIfPresent([String: Int].self, forKey: .longestSession) ?? [:]
        nudges = try c.decodeIfPresent([String: Int].self, forKey: .nudges) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case day, minutes, longestSession, nudges
    }
}

/// Persistent state shared between the app and its extensions through an App Group.
///
/// Every value is a small JSON blob in `UserDefaults(suiteName:)`, which both
/// the app and the DeviceActivityMonitor extension can read and write.
public final class SharedStore: @unchecked Sendable {
    /// Must match the App Group in both targets' entitlements (see project.yml).
    public static let appGroupID = "group.com.yourcompany.zensave"

    public static let shared = SharedStore()

    private let defaults: UserDefaults
    private let calendar: Calendar

    public init(defaults: UserDefaults? = UserDefaults(suiteName: SharedStore.appGroupID), calendar: Calendar = .current) {
        self.defaults = defaults ?? .standard
        self.calendar = calendar
    }

    private enum Key {
        static let apps = "zen.apps"
        static let alternatives = "zen.alternatives"
        static let choices = "zen.choices"
        static let habitOverrides = "zen.habitOverrides"
        static let profile = "zen.profile"
        static let usage = "zen.usage"
        static let sessions = "zen.sessions"
    }

    private func load<T: Decodable>(_ key: String, as _: T.Type) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    // MARK: Configuration (written by the app)

    public var apps: [TrackedApp] {
        // Limits are session limits; older versions stored daily limits of up to 120 minutes.
        get {
            (load(Key.apps, as: [TrackedApp].self) ?? Defaults.apps).map { app in
                var a = app
                a.limit = SessionRule.clamped(a.limit)
                return a
            }
        }
        set { save(newValue, Key.apps) }
    }

    public var alternatives: [Alternative] {
        get { load(Key.alternatives, as: [Alternative].self) ?? Defaults.alternatives }
        set { save(newValue, Key.alternatives) }
    }

    public var profile: CoachProfile {
        get { load(Key.profile, as: CoachProfile.self) ?? CoachProfile() }
        set { save(newValue, Key.profile) }
    }

    // MARK: History

    public var choices: [Choice] {
        get { load(Key.choices, as: [Choice].self) ?? [] }
        set { save(newValue, Key.choices) }
    }

    public func recordChoice(_ choice: String, app: String, at date: Date = Date()) {
        var all = choices
        all.append(Choice(at: date, app: app, choice: choice))
        // Keep the store small: nothing older than ~90 days is shown anywhere.
        let cutoff = date.addingTimeInterval(-90 * 86_400)
        choices = all.filter { $0.at >= cutoff }
    }

    public var habitOverrides: HabitOverrides {
        get { load(Key.habitOverrides, as: HabitOverrides.self) ?? [:] }
        set { save(newValue, Key.habitOverrides) }
    }

    // MARK: Today's usage (written by the extension)

    /// Today's usage; a stored value from an earlier day reads as empty.
    public func usage(now: Date = Date()) -> DailyUsage {
        let today = Habit.dayKey(now, calendar: calendar)
        if let stored = load(Key.usage, as: DailyUsage.self), stored.day == today { return stored }
        return DailyUsage(day: today)
    }

    /// Records that `appID` has been used for `minutes` today. Usage only goes up within a day.
    /// This only feeds the Today screen; nudges come from sessions (see `Session.swift`).
    public func reportUsage(appID: String, minutes: Int, now: Date = Date()) {
        var u = usage(now: now)
        u.minutes[appID] = max(u.minutes[appID] ?? 0, minutes)
        saveUsage(u)
    }

    func saveUsage(_ usage: DailyUsage) {
        save(usage, Key.usage)
    }

    // MARK: Sessions (written by the app and the extension)

    var sessions: [String: SessionState] {
        get { load(Key.sessions, as: [String: SessionState].self) ?? [:] }
        set { save(newValue, Key.sessions) }
    }
}
