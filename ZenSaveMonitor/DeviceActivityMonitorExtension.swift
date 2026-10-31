import DeviceActivity
import Foundation
import UserNotifications

/// Runs in the background, out of process, whenever iOS reports Screen Time progress.
///
/// The app registers one daily activity with several events per tracked app:
/// `"<appID>.<minutes>"` at every 5 minutes up to the limit, plus one exactly at the limit.
/// Each event that fires tells us "this app has now been used for N minutes today".
/// When N reaches the limit we post the nudge notification.
///
/// Extensions get a small memory budget (~6 MB), so keep this lean: no UI, no AI.
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    private let store = SharedStore.shared

    // No reset in intervalDidStart: it also fires when the app reschedules mid-day (e.g. a
    // limit changed), and SharedStore already starts fresh usage when the calendar day changes.

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard let parsed = ScreenTimeEvent.parse(event.rawValue),
              let app = store.reportUsage(appID: parsed.appID, minutes: parsed.minutes) else { return }
        postNudge(for: app)
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
        let request = UNNotificationRequest(
            identifier: "nudge.\(app.id).\(Habit.dayKey(Date()))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
