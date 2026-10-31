import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// Wraps Apple's Screen Time APIs:
/// - FamilyControls: asks the user for permission and lets them pick apps (FamilyActivityPicker).
/// - DeviceActivity: schedules daily monitoring with usage thresholds, delivered to ZenSaveMonitor.
///
/// iOS never tells the app *which* app a token is (privacy), so every tracked entry pairs a
/// user-picked selection with the name the user sees in the nudge ("Instagram").
@MainActor
final class ScreenTimeManager {
    static let shared = ScreenTimeManager()

    private let center = DeviceActivityCenter()
    private let selectionsKey = "zen.selections"
    private let defaults = UserDefaults(suiteName: SharedStore.appGroupID) ?? .standard

    var isAuthorized: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }

    /// Shows the system Screen Time permission prompt (individual, not parental, authorization).
    func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }

    // MARK: Selections per tracked app

    func selection(for appID: String) -> FamilyActivitySelection {
        guard let data = selectionsData[appID],
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else { return FamilyActivitySelection() }
        return selection
    }

    func setSelection(_ selection: FamilyActivitySelection, for appID: String) {
        var all = selectionsData
        all[appID] = try? JSONEncoder().encode(selection)
        selectionsData = all
    }

    func hasSelection(for appID: String) -> Bool {
        let s = selection(for: appID)
        return !(s.applicationTokens.isEmpty && s.categoryTokens.isEmpty && s.webDomainTokens.isEmpty)
    }

    private var selectionsData: [String: Data] {
        get { (defaults.dictionary(forKey: selectionsKey) as? [String: Data]) ?? [:] }
        set { defaults.set(newValue, forKey: selectionsKey) }
    }

    // MARK: Monitoring

    /// (Re)starts the all-day schedule with one event per 5-minute mark per tracked app.
    /// Call whenever apps, selections or limits change.
    func startMonitoring(apps: [TrackedApp]) throws {
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for app in apps where hasSelection(for: app.id) {
            let s = selection(for: app.id)
            for minutes in ScreenTimeEvent.thresholds(limit: app.limit) {
                let name = DeviceActivityEvent.Name(ScreenTimeEvent.name(appID: app.id, minutes: minutes))
                events[name] = DeviceActivityEvent(
                    applications: s.applicationTokens,
                    categories: s.categoryTokens,
                    webDomains: s.webDomainTokens,
                    threshold: DateComponents(minute: minutes),
                    // Count usage from earlier today when monitoring starts mid-day.
                    includesPastActivity: true
                )
            }
        }

        let activity = DeviceActivityName(ScreenTimeEvent.activityName)
        center.stopMonitoring([activity])
        guard !events.isEmpty else { return }

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        try center.startMonitoring(activity, during: schedule, events: events)
    }

    func stopMonitoring() {
        center.stopMonitoring()
    }
}
