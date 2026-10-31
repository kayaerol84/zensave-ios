import Foundation

// Swift port of src/lib/nudge.ts from the web prototype.
// Keep these in sync with the tests in ZenCoreTests/NudgeTests.swift.

/// An app (or group of apps) whose scrolling time is tracked against a daily limit.
public struct TrackedApp: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var emoji: String
    /// Minutes used today.
    public var minutes: Int
    /// Daily limit in minutes. 0 disables the nudge.
    public var limit: Int

    public init(id: String, name: String, emoji: String, minutes: Int = 0, limit: Int) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.minutes = minutes
        self.limit = limit
    }
}

/// Something better to do than scrolling (Imprint, the gym, a walk, ...).
public struct Alternative: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var emoji: String
    public var enabled: Bool

    public init(id: String, name: String, emoji: String, enabled: Bool) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.enabled = enabled
    }
}

/// What the user said they did after a nudge.
public struct Choice: Codable, Hashable, Sendable {
    public var at: Date
    public var app: String
    public var choice: String

    public init(at: Date, app: String, choice: String) {
        self.at = at
        self.app = app
        self.choice = choice
    }
}

/// Manual marks on the habit grid, keyed by `dayKey`. An explicit mark wins over derived data.
public typealias HabitOverrides = [String: Bool]

public enum Nudge {
    /// The choice that means the user did not switch.
    public static let keptScrolling = "kept scrolling"
    /// Offered next to the enabled alternatives.
    public static let somethingElse = "something else"

    /// A nudge fires once the time spent in an app reaches its limit.
    public static func shouldNudge(minutes: Int, limit: Int) -> Bool {
        limit > 0 && minutes >= limit
    }

    public static func shouldNudge(_ app: TrackedApp) -> Bool {
        shouldNudge(minutes: app.minutes, limit: app.limit)
    }

    public static func formatMinutes(_ minutes: Int) -> String {
        let m = max(0, minutes)
        if m < 60 { return "\(m) min" }
        let h = m / 60
        let r = m % 60
        return r == 0 ? "\(h)h" : "\(h)h \(r)m"
    }

    /// "Imprint", "Imprint or the gym", "Imprint, the gym or a walk".
    public static func joinedTargets(_ alternatives: [Alternative]) -> String {
        let names = alternatives.filter(\.enabled).map(\.name)
        switch names.count {
        case 0: return "something offline"
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " or " + names[names.count - 1]
        }
    }

    public static func message(appName: String, minutes: Int, alternatives: [Alternative]) -> String {
        "You spent \(formatMinutes(minutes)) in \(appName) and it is time to switch to \(joinedTargets(alternatives))."
    }

    /// The buttons offered after a nudge: enabled alternatives, then "something else" and "kept scrolling".
    public static func choiceOptions(_ alternatives: [Alternative]) -> [String] {
        alternatives.filter(\.enabled).map(\.name) + [somethingElse, keptScrolling]
    }
}

// MARK: - Weekly summary

public struct WeeklySummary: Equatable, Sendable {
    public struct Count: Equatable, Sendable {
        public var choice: String
        public var count: Int
        public init(choice: String, count: Int) {
            self.choice = choice
            self.count = count
        }
    }

    public var total: Int
    /// Most picked first; ties keep the order they were first picked.
    public var byChoice: [Count]
    /// Choices in the window, oldest first.
    public var recent: [Choice]

    /// Times the user picked something other than "kept scrolling".
    public var switches: Int {
        byChoice.filter { $0.choice != Nudge.keptScrolling }.reduce(0) { $0 + $1.count }
    }
}

extension Nudge {
    /// Choices from the last 7 days, counted per activity, most picked first.
    public static func weeklySummary(_ choices: [Choice], now: Date = Date()) -> WeeklySummary {
        let since = now.addingTimeInterval(-7 * 86_400)
        let recent = choices.filter { $0.at >= since && $0.at <= now }
        var order: [String] = []
        var counts: [String: Int] = [:]
        for c in recent {
            if counts[c.choice] == nil { order.append(c.choice) }
            counts[c.choice, default: 0] += 1
        }
        let byChoice = order.enumerated()
            .sorted { lhs, rhs in
                let l = counts[lhs.element]!, r = counts[rhs.element]!
                return l != r ? l > r : lhs.offset < rhs.offset
            }
            .map { WeeklySummary.Count(choice: $0.element, count: counts[$0.element]!) }
        return WeeklySummary(total: recent.count, byChoice: byChoice, recent: recent)
    }
}

// MARK: - Habit tracker

public struct HabitProgress: Equatable, Sendable {
    public var streak: Int
    public var last30: Int
    public init(streak: Int, last30: Int) {
        self.streak = streak
        self.last30 = last30
    }
}

public enum Habit {
    /// Local calendar day key, e.g. "2026-10-31".
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Day keys (within the last 42 days) with at least one switch, i.e. any choice other than "kept scrolling".
    public static func autoSwitchedDays(_ choices: [Choice], now: Date = Date(), calendar: Calendar = .current) -> Set<String> {
        let since = now.addingTimeInterval(-42 * 86_400)
        var days = Set<String>()
        for c in choices where c.at >= since && c.at <= now && c.choice != Nudge.keptScrolling {
            days.insert(dayKey(c.at, calendar: calendar))
        }
        return days
    }

    /// A 6-week grid of day keys ending today (Monday first); leading cells are nil. Always 42 cells.
    public static func grid(now: Date = Date(), calendar: Calendar = .current) -> [String?] {
        let end = noon(of: now, calendar: calendar)
        // Calendar weekday: Sunday = 1 ... Saturday = 7. Monday-first offset:
        let lead = (calendar.component(.weekday, from: end) + 5) % 7
        var cells: [String?] = Array(repeating: nil, count: lead)
        for i in stride(from: 41 - lead, through: 0, by: -1) {
            let d = calendar.date(byAdding: .day, value: -i, to: end)!
            cells.append(dayKey(d, calendar: calendar))
        }
        return cells
    }

    /// Whether a day counts as switched: an explicit mark wins, otherwise it is derived from recorded choices.
    public static func isSwitched(_ key: String, auto: Set<String>, overrides: HabitOverrides) -> Bool {
        overrides[key] ?? auto.contains(key)
    }

    /// Current streak of switched days ending today, and how many of the last 30 days count as switched.
    public static func progress(auto: Set<String>, overrides: HabitOverrides, now: Date = Date(), calendar: Calendar = .current) -> HabitProgress {
        let today = noon(of: now, calendar: calendar)
        func switchedOn(_ offset: Int) -> Bool {
            let d = calendar.date(byAdding: .day, value: -offset, to: today)!
            return isSwitched(dayKey(d, calendar: calendar), auto: auto, overrides: overrides)
        }
        var streak = 0
        while streak < 365 && switchedOn(streak) { streak += 1 }
        let last30 = (0..<30).filter(switchedOn).count
        return HabitProgress(streak: streak, last30: last30)
    }

    private static func noon(of date: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }
}

// MARK: - Defaults (same as the prototype)

public enum Defaults {
    public static let apps: [TrackedApp] = [
        TrackedApp(id: "ig", name: "Instagram", emoji: "📸", minutes: 0, limit: 20),
        TrackedApp(id: "tt", name: "TikTok", emoji: "🎵", minutes: 0, limit: 15),
        TrackedApp(id: "x", name: "X", emoji: "✖️", minutes: 0, limit: 15),
        TrackedApp(id: "yt", name: "YouTube", emoji: "▶️", minutes: 0, limit: 30),
    ]

    /// Demo starting minutes, as in the web prototype.
    public static let demoMinutes: [String: Int] = ["ig": 12, "tt": 6, "x": 3, "yt": 9]

    public static let alternatives: [Alternative] = [
        Alternative(id: "imprint", name: "Imprint", emoji: "📚", enabled: true),
        Alternative(id: "gym", name: "the gym", emoji: "🏋️", enabled: true),
        Alternative(id: "walk", name: "a walk", emoji: "🚶", enabled: false),
        Alternative(id: "read", name: "a book", emoji: "📖", enabled: false),
    ]
}
