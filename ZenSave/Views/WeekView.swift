import SwiftUI

struct WeekView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let summary = model.weeklySummary
        let progress = model.habitProgress

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Times you switched in the last 7 days").font(.subheadline).foregroundStyle(Theme.mutedForeground)
                Text("\(summary.switches)").font(Theme.display(64))
                Text("out of \(summary.total) nudges answered").font(.subheadline).foregroundStyle(Theme.mutedForeground)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()

            HabitCard(progress: progress)

            if summary.byChoice.isEmpty {
                Text("No choices yet. When an alert appears, tap what you did instead.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.mutedForeground)
            } else {
                VStack(spacing: 12) {
                    ForEach(summary.byChoice, id: \.choice) { c in
                        HStack {
                            Text(c.choice.prefix(1).uppercased() + c.choice.dropFirst()).font(.body.weight(.semibold))
                            Spacer()
                            Text("\(c.count)×")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(c.choice == Nudge.keptScrolling ? Theme.destructive : Theme.primary)
                        }
                        .padding(16)
                        .cardSurface()
                    }
                }
            }

            if !summary.recent.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Recent")
                    ForEach(Array(summary.recent.reversed().prefix(10).enumerated()), id: \.offset) { _, c in
                        (Text("\(c.at.formatted(.dateTime.weekday(.abbreviated))) · \(c.app) → ")
                            .foregroundStyle(Theme.mutedForeground)
                         + Text(c.choice))
                            .font(.subheadline)
                    }
                }
            }
        }
    }
}

private struct HabitCard: View {
    @Environment(AppModel.self) private var model
    let progress: HabitProgress

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        let today = Habit.dayKey(Date())

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Days you switched").font(.subheadline).foregroundStyle(Theme.mutedForeground)
                    (Text("\(progress.last30)").font(Theme.display(40))
                     + Text(" of last 30").font(.title3).foregroundStyle(Theme.mutedForeground))
                }
                Spacer()
                Text("🔥 \(progress.streak)-day streak")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.primary)
            }

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, d in
                    Text(d).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.mutedForeground)
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(Habit.grid().enumerated()), id: \.offset) { _, key in
                    if let key {
                        let on = model.isSwitched(key)
                        Button { model.toggleHabitDay(key) } label: {
                            Text("\(Int(key.suffix(2)) ?? 0)")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(on ? Theme.primary : Theme.muted, in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(on ? Theme.primaryForeground : Theme.mutedForeground)
                                .overlay {
                                    if key == today {
                                        RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.primary, lineWidth: 2).padding(-2)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(key) \(on ? "switched" : "not switched")")
                    } else {
                        Color.clear.frame(height: 32)
                    }
                }
            }

            Text("Filled days are days you switched. They fill in when you pick an activity after an alert — tap a day to fix it.")
                .font(.caption)
                .foregroundStyle(Theme.mutedForeground)
        }
        .padding(20)
        .cardSurface()
    }
}
