import Foundation
import UserNotifications

/// Registers the nudge notification's "What did you do instead?" buttons and
/// turns taps on them into recorded choices.
enum NotificationManager {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Notification actions are fixed per category, so re-register whenever alternatives change.
    static func registerCategories(alternatives: [Alternative]) {
        let actions = Nudge.choiceOptions(alternatives).map { choice in
            UNNotificationAction(
                identifier: NudgeNotification.choicePrefix + choice,
                title: choice.prefix(1).uppercased() + choice.dropFirst(),
                options: choice == Nudge.keptScrolling ? [.destructive] : []
            )
        }
        let category = UNNotificationCategory(
            identifier: NudgeNotification.category,
            actions: actions,
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
