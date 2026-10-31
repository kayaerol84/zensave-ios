import Foundation

/// Identifiers shared by the app (which registers notification actions and Screen Time events)
/// and the monitor extension (which posts notifications and receives events).
public enum NudgeNotification {
    public static let category = "zen.nudge"
    public static let appNameKey = "appName"
    public static let minutesKey = "minutes"
    /// Action identifiers are `choicePrefix + <choice text>`.
    public static let choicePrefix = "choice:"
}

/// Screen Time event names are `"<appID>.<minutes>"`, e.g. `"ig.20"`.
public enum ScreenTimeEvent {
    public static let activityName = "zen.daily"
    /// Progress is sampled every `step` minutes so the Today screen can show usage.
    public static let step = 5

    public static func name(appID: String, minutes: Int) -> String {
        "\(appID).\(minutes)"
    }

    public static func parse(_ raw: String) -> (appID: String, minutes: Int)? {
        guard let dot = raw.lastIndex(of: "."),
              let minutes = Int(raw[raw.index(after: dot)...]) else { return nil }
        let appID = String(raw[..<dot])
        return appID.isEmpty ? nil : (appID, minutes)
    }

    /// Minute marks to register for one app: every `step` up to the limit, plus the limit itself.
    public static func thresholds(limit: Int) -> [Int] {
        guard limit > 0 else { return [] }
        var marks = Array(stride(from: step, to: limit, by: step))
        marks.append(limit)
        return marks
    }
}
