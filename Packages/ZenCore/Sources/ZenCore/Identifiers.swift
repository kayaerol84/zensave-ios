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

/// Daily usage events (for the Today screen) are named `"<appID>.<minutes>"`, e.g. `"ig.20"`.
/// Nudges don't come from these; they come from sessions (see `Session.swift`).
public enum ScreenTimeEvent {
    public static let activityName = "zen.daily"
    /// Usage is sampled every `step` minutes for the first hour...
    public static let step = 5
    /// ...then every `longStep` minutes up to `ceiling`.
    public static let longStep = 15
    public static let ceiling = 180

    public static func name(appID: String, minutes: Int) -> String {
        "\(appID).\(minutes)"
    }

    public static func parse(_ raw: String) -> (appID: String, minutes: Int)? {
        guard let dot = raw.lastIndex(of: "."),
              let minutes = Int(raw[raw.index(after: dot)...]) else { return nil }
        let appID = String(raw[..<dot])
        return appID.isEmpty ? nil : (appID, minutes)
    }

    /// Minute marks to register for one app's daily usage: 5, 10, ... 60, 75, 90, ... 180.
    public static let thresholds: [Int] =
        Array(stride(from: step, through: 60, by: step)) + Array(stride(from: 60 + longStep, through: ceiling, by: longStep))
}
