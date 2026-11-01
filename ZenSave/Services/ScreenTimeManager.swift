import FamilyControls
import Foundation

/// Wraps Apple's Screen Time APIs for the app:
/// - FamilyControls: asks the user for permission and lets them pick apps (FamilyActivityPicker).
/// - DeviceActivity (through `SessionScheduler`): watches each tracked app for long sessions;
///   the ZenSaveMonitor extension gets the events and nudges.
///
/// iOS never tells the app *which* app a token is (privacy), so every tracked entry pairs a
/// user-picked selection with the name the user sees in the nudge ("Instagram").
@MainActor
final class ScreenTimeManager {
    static let shared = ScreenTimeManager()

    private let scheduler = SessionScheduler()

    var isAuthorized: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }

    /// Shows the system Screen Time permission prompt (individual, not parental, authorization).
    func requestAuthorization() async throws {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }

    // MARK: Selections per tracked app

    func selection(for appID: String) -> FamilyActivitySelection {
        scheduler.selection(for: appID)
    }

    func setSelection(_ selection: FamilyActivitySelection, for appID: String) {
        scheduler.setSelection(selection, for: appID)
    }

    func removeSelection(for appID: String) {
        scheduler.removeSelection(for: appID)
    }

    func hasSelection(for appID: String) -> Bool {
        scheduler.hasSelection(for: appID)
    }

    // MARK: Monitoring

    /// Restarts all monitoring from the saved configuration. Call whenever apps,
    /// picked apps or session limits change (it ends any session in progress).
    func restartMonitoring() throws {
        try scheduler.restartAll()
    }

    /// Re-arms session watches that stopped, without interrupting running ones.
    func ensureMonitoring() throws {
        try scheduler.ensureRunning()
    }

    func stopMonitoring() {
        scheduler.stopAll()
    }
}
