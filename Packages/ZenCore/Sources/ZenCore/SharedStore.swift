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

/// Minutes used per tracked app on one calendar day. Written by the Screen Time
/// monitor extension, read by the app. Resets when the day changes.
public struct DailyUsage: Codable, Equatable, Sendable {
    public var day: String
    public var minutes: [String: Int]
    /// Apps already nudged on `day`, so each app nudges at most once a day.
    public var nudged: Set<String>

    public init(day: String, minutes: [String: Int] = [:], nudged: Set<String> = []) {
        self.day = day
        self.minutes = minutes
        self.nudged = nudged
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
        get { load(Key.apps, as: [TrackedApp].self) ?? Defaults.apps }
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

    /// Records that `appID` reached `minutes` today. Usage only goes up within a day.
    /// Returns the app with today's minutes filled in if this report should fire a nudge
    /// (it reached the limit and has not been nudged yet today), otherwise nil.
    @discardableResult
    public func reportUsage(appID: String, minutes: Int, now: Date = Date()) -> TrackedApp? {
        var u = usage(now: now)
        u.minutes[appID] = max(u.minutes[appID] ?? 0, minutes)
        var fire: TrackedApp?
        if var app = apps.first(where: { $0.id == appID }) {
            app.minutes = u.minutes[appID] ?? 0
            if Nudge.shouldNudge(app) && !u.nudged.contains(appID) {
                u.nudged.insert(appID)
                fire = app
            }
        }
        save(u, Key.usage)
        return fire
    }
}
