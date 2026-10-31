import FamilyControls
import Foundation
import Observation

/// A nudge on screen: the in-app version of the notification, with the "What did you do instead?" buttons.
struct ActiveNudge: Equatable {
    var appName: String
    var minutes: Int
    var message: String
    var isThinking = false
}

/// App state and actions. Mirrors the state in the prototype's `Index` component.
@MainActor
@Observable
final class AppModel {
    enum Mode: String {
        /// Fake scroll sessions inside the app (works in the simulator).
        case demo
        /// Real usage from Screen Time, nudges from the background extension.
        case screenTime
    }

    private let store: SharedStore
    private let screenTime: ScreenTimeManager

    private(set) var mode: Mode
    var apps: [TrackedApp] = []
    private(set) var alternatives: [Alternative] = []
    private(set) var choices: [Choice] = []
    private(set) var habitOverrides: HabitOverrides = [:]
    var profile: CoachProfile = CoachProfile() {
        didSet { store.profile = profile }
    }

    var activeNudge: ActiveNudge?
    var toast: String?
    var errorMessage: String?
    private(set) var scrollingAppID: String?
    /// Minutes in the current demo scroll session.
    private(set) var demoSessionMinutes = 0
    /// Longest session that triggered a nudge today, per app (Screen Time mode).
    private(set) var longestSessions: [String: Int] = [:]

    @ObservationIgnored private var demoTask: Task<Void, Never>?

    init(store: SharedStore = .shared) {
        self.store = store
        let manager = ScreenTimeManager.shared
        self.screenTime = manager
        let saved = Mode(rawValue: UserDefaults.standard.string(forKey: "zen.mode") ?? "") ?? .demo
        self.mode = (saved == .screenTime && !manager.isAuthorized) ? .demo : saved
        reload()
    }

    // MARK: Loading

    func reload() {
        alternatives = store.alternatives
        profile = store.profile
        choices = store.choices
        habitOverrides = store.habitOverrides
        let configured = store.apps
        switch mode {
        case .demo:
            // Keep demo minutes across reloads; start from the prototype's numbers.
            let current = Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0.minutes) })
            apps = configured.map { app in
                var a = app
                a.minutes = current[app.id] ?? Defaults.demoMinutes[app.id] ?? 0
                return a
            }
        case .screenTime:
            let usage = store.usage()
            longestSessions = usage.longestSession
            apps = configured.map { app in
                var a = app
                a.minutes = usage.minutes[app.id] ?? 0
                return a
            }
        }
        NotificationManager.registerCategories(alternatives: alternatives)
    }

    var totalMinutes: Int { apps.reduce(0) { $0 + $1.minutes } }

    /// Called when the app comes to the foreground.
    func becameActive() {
        reload()
        guard mode == .screenTime else { return }
        // Repair session watches the extension couldn't restart, without cutting running ones short.
        try? screenTime.ensureMonitoring()
    }

    // MARK: Screen Time

    func enableScreenTime() async {
        do {
            try await screenTime.requestAuthorization()
            _ = await NotificationManager.requestAuthorization()
            stopScrolling()
            setMode(.screenTime)
            restartMonitoring()
        } catch {
            errorMessage = "Screen Time permission wasn't granted. Unscroll needs it to see how long you scroll. (It doesn't work in the simulator — use demo mode there.)"
        }
    }

    func useDemoMode() {
        screenTime.stopMonitoring()
        setMode(.demo)
    }

    private func setMode(_ newMode: Mode) {
        mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: "zen.mode")
        apps = []
        reload()
    }

    func selection(for appID: String) -> FamilyActivitySelection {
        screenTime.selection(for: appID)
    }

    func hasSelection(for appID: String) -> Bool {
        screenTime.hasSelection(for: appID)
    }

    func setSelection(_ selection: FamilyActivitySelection, for appID: String) {
        screenTime.setSelection(selection, for: appID)
        restartMonitoring()
    }

    private func restartMonitoring() {
        guard mode == .screenTime else { return }
        do {
            try screenTime.restartMonitoring()
        } catch {
            errorMessage = "Couldn't start Screen Time monitoring: \(error.localizedDescription)"
        }
    }

    // MARK: Limits & tracked apps

    /// Sets the session limit: minutes in a row before a nudge.
    func setLimit(_ limit: Int, for appID: String) {
        guard let i = apps.firstIndex(where: { $0.id == appID }) else { return }
        apps[i].limit = SessionRule.clamped(limit)
        // Persisted by `saveApps()` when the slider is released.
    }

    func rename(_ appID: String, name: String, emoji: String) {
        guard let i = apps.firstIndex(where: { $0.id == appID }) else { return }
        apps[i].name = name
        apps[i].emoji = emoji
        saveApps()
    }

    func addApp(name: String, emoji: String) {
        // No dots: activity and event names use "." as a separator.
        let id = "app" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
        apps.append(TrackedApp(id: id, name: name, emoji: emoji.isEmpty ? "📱" : emoji, minutes: 0, limit: SessionRule.defaultLimit))
        saveApps()
    }

    func removeApp(_ appID: String) {
        apps.removeAll { $0.id == appID }
        if scrollingAppID == appID { stopScrolling() }
        screenTime.removeSelection(for: appID)
        saveApps()
    }

    /// Saved when the limit slider is released, so monitoring isn't rescheduled on every tick.
    func saveApps() {
        store.apps = apps.map { var a = $0; a.minutes = 0; return a }
        restartMonitoring()
    }

    // MARK: Alternatives

    func toggleAlternative(_ id: String) {
        guard let i = alternatives.firstIndex(where: { $0.id == id }) else { return }
        alternatives[i].enabled.toggle()
        store.alternatives = alternatives
        NotificationManager.registerCategories(alternatives: alternatives)
    }

    func addAlternative(name: String, emoji: String) {
        alternatives.append(Alternative(id: UUID().uuidString, name: name, emoji: emoji.isEmpty ? "✨" : emoji, enabled: true))
        store.alternatives = alternatives
        NotificationManager.registerCategories(alternatives: alternatives)
    }

    // MARK: Demo scrolling (prototype: 250 ms = 1 minute)

    /// Starts or stops a fake scroll session. Like the real thing, it nudges every
    /// `limit` minutes in a row, and stopping ends the session.
    func toggleScroll(_ appID: String) {
        if scrollingAppID == appID { stopScrolling(); return }
        stopScrolling()
        scrollingAppID = appID
        demoSessionMinutes = 0
        demoTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled else { return }
                self.tickDemo(appID)
            }
        }
    }

    func stopScrolling() {
        demoTask?.cancel()
        demoTask = nil
        scrollingAppID = nil
        demoSessionMinutes = 0
    }

    private func tickDemo(_ appID: String) {
        guard let i = apps.firstIndex(where: { $0.id == appID }) else { return }
        apps[i].minutes += 1
        demoSessionMinutes += 1
        let limit = SessionRule.clamped(apps[i].limit)
        if demoSessionMinutes % limit == 0 {
            // Keep "scrolling" until the user answers, so repeat nudges can be seen.
            presentNudge(appName: apps[i].name, minutes: demoSessionMinutes)
        }
    }

    func resetDemo() {
        stopScrolling()
        activeNudge = nil
        apps = apps.map { var a = $0; a.minutes = Defaults.demoMinutes[a.id] ?? 0; return a }
    }

    // MARK: Nudges & choices

    func presentNudge(appName: String, minutes: Int) {
        let message = Nudge.message(appName: appName, minutes: minutes, alternatives: alternatives)
        let wantsAI = profile.useAI && !profile.isEmpty && SuggestionService.isAvailable
        activeNudge = ActiveNudge(appName: appName, minutes: minutes, message: message, isThinking: wantsAI)
        guard wantsAI else { return }
        let profile = profile
        Task {
            let suggestion = await SuggestionService.suggest(appName: appName, minutes: minutes, profile: profile)
            guard activeNudge?.appName == appName else { return }
            if let suggestion { activeNudge?.message = suggestion }
            activeNudge?.isThinking = false
        }
    }

    var choiceOptions: [String] { Nudge.choiceOptions(alternatives) }

    func recordChoice(_ choice: String) {
        let app = activeNudge?.appName ?? ""
        store.recordChoice(choice, app: app)
        choices = store.choices
        activeNudge = nil
        // Switching to something else ends the demo session.
        if choice != Nudge.keptScrolling { stopScrolling() }
        toast = choice == Nudge.keptScrolling ? "Logged. Tomorrow's another chance." : "Nice — logged \(choice)."
    }

    /// Called when a choice was made from the notification's buttons (store already updated).
    func choicesChangedExternally() {
        choices = store.choices
    }

    // MARK: Week / habit tracker

    var weeklySummary: WeeklySummary { Nudge.weeklySummary(choices) }
    var autoSwitched: Set<String> { Habit.autoSwitchedDays(choices) }
    var habitProgress: HabitProgress { Habit.progress(auto: autoSwitched, overrides: habitOverrides) }

    func isSwitched(_ key: String) -> Bool {
        Habit.isSwitched(key, auto: autoSwitched, overrides: habitOverrides)
    }

    func toggleHabitDay(_ key: String) {
        habitOverrides[key] = !isSwitched(key)
        store.habitOverrides = habitOverrides
    }
}
