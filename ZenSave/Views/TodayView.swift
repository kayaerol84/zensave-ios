import FamilyControls
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Scrolling time today").font(.subheadline).foregroundStyle(Theme.mutedForeground)
                Text(Nudge.formatMinutes(model.totalMinutes)).font(Theme.display(64))
                Text(subtitle).font(.subheadline).foregroundStyle(Theme.mutedForeground)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()

            VStack(spacing: 12) {
                ForEach(model.apps) { app in
                    AppUsageRow(app: app)
                }
            }

            if model.mode == .demo {
                Button("Reset demo") { model.resetDemo() }
                    .font(.subheadline)
                    .underline()
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(maxWidth: .infinity)
                ScreenTimeCallout()
            }
        }
    }

    private var subtitle: String {
        switch model.mode {
        case .screenTime:
            "From Screen Time, updated every \(ScreenTimeEvent.step) minutes."
        case .demo:
            model.scrollingAppID != nil
                ? "Watching your scroll… sped up for the demo"
                : "Tap an app below to fake a scroll session."
        }
    }
}

private struct AppUsageRow: View {
    @Environment(AppModel.self) private var model
    let app: TrackedApp

    var body: some View {
        let over = Nudge.shouldNudge(app)
        let active = model.scrollingAppID == app.id
        let fraction = app.limit > 0 ? min(1, Double(app.minutes) / Double(app.limit)) : 0

        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text(app.emoji).font(.title)
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.body.weight(.semibold))
                    Text("\(Nudge.formatMinutes(app.minutes)) of \(Nudge.formatMinutes(app.limit))")
                        .font(.caption).foregroundStyle(Theme.mutedForeground)
                }
                Spacer()
                switch model.mode {
                case .demo:
                    Button(active ? "Stop" : "Scroll") { model.toggleScroll(app.id) }
                        .buttonStyle(PillButtonStyle(active: active))
                case .screenTime:
                    AppPickerButton(appID: app.id)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.muted)
                    Capsule()
                        .fill(over ? Theme.destructive : Theme.primary)
                        .frame(width: geo.size.width * fraction)
                        .animation(.linear(duration: 0.25), value: fraction)
                }
            }
            .frame(height: 6)
        }
        .padding(16)
        .cardSurface()
    }
}

/// Opens Apple's app picker for one tracked entry. Shows "Pick app" until something is chosen.
struct AppPickerButton: View {
    @Environment(AppModel.self) private var model
    let appID: String
    @State private var isPresented = false
    @State private var selection = FamilyActivitySelection()

    var body: some View {
        let picked = model.hasSelection(for: appID)
        Button(picked ? "Change" : "Pick app") {
            selection = model.selection(for: appID)
            isPresented = true
        }
        .buttonStyle(PillButtonStyle(active: !picked))
        .familyActivityPicker(isPresented: $isPresented, selection: $selection)
        .onChange(of: isPresented) { _, open in
            if !open { model.setSelection(selection, for: appID) }
        }
    }
}

/// Shown in demo mode: explains and turns on real tracking.
private struct ScreenTimeCallout: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Track your real scrolling").font(.headline)
            Text("Unscroll uses Screen Time to notice when you've spent too long in an app — even when Unscroll is closed — and nudges you to switch. Your usage stays on your iPhone.")
                .font(.subheadline)
                .foregroundStyle(Theme.mutedForeground)
            Button("Turn on Screen Time") {
                Task { await model.enableScreenTime() }
            }
            .buttonStyle(PillButtonStyle(active: true))
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }
}
