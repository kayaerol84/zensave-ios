import SwiftUI
import UserNotifications

@main
struct ZenSaveApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appDelegate.model)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { _, phase in
                    // Pick up usage and choices written by the extension / notification buttons.
                    if phase == .active { appDelegate.model.becameActive() }
                }
        }
    }
}

/// Owns the model (so it exists even when the app is cold-launched from a notification) and
/// handles the nudge notification: its buttons record a choice without opening the app,
/// tapping the notification itself opens the in-app nudge (with an AI suggestion if enabled).
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let model = AppModel()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Show the banner even while the app is open (demo mode).
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let appName = info[NudgeNotification.appNameKey] as? String ?? ""
        let minutes = info[NudgeNotification.minutesKey] as? Int ?? 0
        let action = response.actionIdentifier

        if action.hasPrefix(NudgeNotification.choicePrefix) {
            let choice = String(action.dropFirst(NudgeNotification.choicePrefix.count))
            SharedStore.shared.recordChoice(choice, app: appName)
            await MainActor.run { model.choicesChangedExternally() }
        } else if action == UNNotificationDefaultActionIdentifier {
            await MainActor.run { model.presentNudge(appName: appName, minutes: minutes) }
        }
    }
}
