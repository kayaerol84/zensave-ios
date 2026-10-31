import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// Schedules Screen Time monitoring. Compiled into both the app and the ZenSaveMonitor
/// extension, because the extension starts each next session window itself (see `SessionRule`).
///
/// Activities:
/// - `zen.daily`: repeats every day; samples total usage per app for the Today screen, and its
///   `intervalDidStart` at midnight re-arms any session watch that went missing.
/// - `zen.session.<appID>`: one per tracked app; a one-off window that is either waiting for a
///   session to start ("armed") or watching a session ("watching").
final class SessionScheduler {
    private let center = DeviceActivityCenter()
    private let store: SharedStore
    private let defaults: UserDefaults
    private let selectionsKey = "zen.selections"

    init(store: SharedStore = .shared) {
        self.store = store
        self.defaults = UserDefaults(suiteName: SharedStore.appGroupID) ?? .standard
    }

    // MARK: Selections per tracked app (App Group, so the extension can read them)

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

    func removeSelection(for appID: String) {
        var all = selectionsData
        all[appID] = nil
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

    /// Tracked apps that have a picked app, up to what iOS can monitor at once.
    var monitoredApps: [TrackedApp] {
        Array(store.apps.filter { hasSelection(for: $0.id) }.prefix(SessionActivity.maxTrackedApps))
    }

    // MARK: Starting and stopping

    /// Stops everything and starts fresh: the daily usage activity, and an armed session watch
    /// per tracked app. Call when apps, picked apps or limits change.
    func restartAll() throws {
        center.stopMonitoring()
        for app in store.apps { store.clearSession(appID: app.id) }
        let apps = monitoredApps
        guard !apps.isEmpty else { return }
        try startDaily(apps: apps)
        for app in apps { try arm(appID: app.id) }
    }

    /// Re-arms session watches that are no longer running (e.g. the extension was killed before
    /// it could start the next window). Leaves running ones alone, so a session isn't cut short.
    func ensureRunning() throws {
        let running = Set(center.activities.map(\.rawValue))
        let apps = monitoredApps
        guard !apps.isEmpty else { return }
        if !running.contains(ScreenTimeEvent.activityName) { try startDaily(apps: apps) }
        let now = Date()
        for app in apps {
            let name = SessionActivity.name(appID: app.id)
            // Also re-arm when the stored window is long over: its end was never delivered.
            if !running.contains(name) || store.windowHasEnded(appID: app.id, now: now.addingTimeInterval(-5 * 60)) {
                try arm(appID: app.id)
            }
        }
    }

    func stopAll() {
        center.stopMonitoring()
        for app in store.apps { store.clearSession(appID: app.id) }
    }

    // MARK: Session windows

    /// Waits for the next session of `appID` to start.
    func arm(appID: String) throws {
        let window = store.endSession(appID: appID)
        try start(window, appID: appID)
    }

    /// Starts `window` for `appID` now, replacing its current window.
    /// The new window must already be recorded in the store (so the old window's
    /// `intervalDidEnd` echo is recognised and ignored).
    func start(_ window: SessionWindow, appID: String) throws {
        let s = selection(for: appID)
        let activity = DeviceActivityName(SessionActivity.name(appID: appID))
        let event = DeviceActivityEvent(
            applications: s.applicationTokens,
            categories: s.categoryTokens,
            webDomains: s.webDomainTokens,
            threshold: DateComponents(minute: window.threshold),
            // Count only use from now on: the session clock starts with this window.
            includesPastActivity: false
        )
        let start = Date()
        let end = start.addingTimeInterval(TimeInterval(window.length * 60))
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: Calendar.current.dateComponents(parts, from: start),
            intervalEnd: Calendar.current.dateComponents(parts, from: end),
            repeats: false
        )
        center.stopMonitoring([activity])
        try center.startMonitoring(
            activity,
            during: schedule,
            events: [DeviceActivityEvent.Name(window.eventName): event]
        )
    }

    // MARK: Daily usage

    private func startDaily(apps: [TrackedApp]) throws {
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for app in apps {
            let s = selection(for: app.id)
            for minutes in ScreenTimeEvent.thresholds {
                events[DeviceActivityEvent.Name(ScreenTimeEvent.name(appID: app.id, minutes: minutes))] = DeviceActivityEvent(
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
        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0, second: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
            repeats: true
        )
        try center.startMonitoring(activity, during: schedule, events: events)
    }
}
