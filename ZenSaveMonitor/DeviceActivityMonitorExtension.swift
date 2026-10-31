import DeviceActivity
import Foundation
import UserNotifications

/// Runs in the background, out of process, whenever iOS reports Screen Time progress.
///
/// Session activities (`zen.session.<appID>`) drive the nudges, as a small state machine
/// (see `SessionRule` in ZenCore):
/// - armed window, `armed.1` reached → a session started: watch it.
/// - watching window, `watching.N` reached → the session hit the limit: nudge, keep watching.
/// - watching window ended without reaching it → the session is over: arm again.
///
/// The daily activity (`zen.daily`) only records total usage for the Today screen.
///
/// Extensions get a small memory budget (~6 MB), so keep this lean: no UI, no AI.
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let store = SharedStore.shared
    private lazy var scheduler = SessionScheduler(store: store)

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // The daily activity starts every midnight: a good moment to repair any session
        // watch that stopped (e.g. the phone was off when a window ended).
        if activity.rawValue == ScreenTimeEvent.activityName {
            try? scheduler.ensureRunning()
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard let appID = SessionActivity.appID(from: activity.rawValue),
              store.apps.contains(where: { $0.id == appID }),
              // Ignore the end of a window we just replaced with a new one.
              store.windowHasEnded(appID: appID) else { return }
        // Armed window ran out, or the session went quiet before the limit: wait for the next one.
        try? scheduler.arm(appID: appID)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)

        if activity.rawValue == ScreenTimeEvent.activityName {
            if let parsed = ScreenTimeEvent.parse(event.rawValue) {
                store.reportUsage(appID: parsed.appID, minutes: parsed.minutes)
            }
            return
        }

        guard let appID = SessionActivity.appID(from: activity.rawValue),
              let parsed = SessionWindow.parseEvent(event.rawValue),
              let result = store.handleSessionEvent(appID: appID, phase: parsed.phase, minutes: parsed.minutes)
        else { return }

        if let app = result.nudge { postNudge(for: app) }
        try? scheduler.start(result.next, appID: appID)
    }

    private func postNudge(for app: TrackedApp) {
        let content = UNMutableNotificationContent()
        content.title = "Time to switch ✋"
        content.body = Nudge.message(appName: app.name, minutes: app.minutes, alternatives: store.alternatives)
        content.sound = .default
        content.categoryIdentifier = NudgeNotification.category
        content.interruptionLevel = .timeSensitive
        content.userInfo = [
            NudgeNotification.appNameKey: app.name,
            NudgeNotification.minutesKey: app.minutes,
        ]
        // Same identifier per app: a repeat nudge replaces the previous one instead of piling up.
        let request = UNNotificationRequest(identifier: "nudge.\(app.id)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
