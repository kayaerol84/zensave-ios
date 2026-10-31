import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case today, limits, switchTo, coach, week
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .limits: "Limits"
        case .switchTo: "Switch to"
        case .coach: "My goals"
        case .week: "This week"
        }
    }

    var tabLabel: String {
        switch self {
        case .switchTo: "Switch to"
        case .coach: "Goals"
        default: rawValue.capitalized
        }
    }

    var symbol: String {
        switch self {
        case .today: "hourglass"
        case .limits: "slider.horizontal.3"
        case .switchTo: "arrow.triangle.swap"
        case .coach: "sparkles"
        case .week: "calendar"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: AppTab = .today

    var body: some View {
        TabView(selection: $tab) {
            ForEach(AppTab.allCases) { t in
                screen(for: t)
                    .tabItem { Label(t.tabLabel, systemImage: t.symbol) }
                    .tag(t)
            }
        }
        .tint(Theme.primary)
        .overlay(alignment: .top) {
            if let nudge = model.activeNudge {
                NudgeBanner(nudge: nudge)
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                ToastView(text: toast)
                    .padding(.bottom, 70)
                    .task(id: toast) {
                        try? await Task.sleep(for: .seconds(2.5))
                        if !Task.isCancelled { model.toast = nil }
                    }
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.7), value: model.activeNudge)
        .animation(.easeInOut, value: model.toast)
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        Screen(title: tab.title) {
            switch tab {
            case .today: TodayView()
            case .limits: LimitsView()
            case .switchTo: SwitchView()
            case .coach: CoachView()
            case .week: WeekView()
            }
        }
    }
}

/// Shared page chrome: eyebrow + big serif title, dark background, scrolling content.
struct Screen<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Unscroll")
                    Text(title).font(Theme.display(40))
                }
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.foreground)
    }
}

/// The in-app nudge, styled like an iOS notification (prototype's `.nudge-banner`).
struct NudgeBanner: View {
    @Environment(AppModel.self) private var model
    let nudge: ActiveNudge

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("U")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 20, height: 20)
                    .background(Theme.primary, in: RoundedRectangle(cornerRadius: 5))
                    .foregroundStyle(Theme.primaryForeground)
                Text("UNSCROLL · now").font(.caption).foregroundStyle(Theme.mutedForeground)
                Spacer()
                Button { model.activeNudge = nil } label: {
                    Image(systemName: "xmark").font(.caption.weight(.bold))
                }
                .foregroundStyle(Theme.mutedForeground)
                .accessibilityLabel("Dismiss")
            }
            Text("Time to switch ✋").font(.headline)
            Text(nudge.message).font(.subheadline).foregroundStyle(Theme.mutedForeground)
            if nudge.isThinking {
                Text("Finding something that fits your goals…").font(.caption).foregroundStyle(Theme.primary)
            }
            Text("What did you do instead?")
                .font(.caption).foregroundStyle(Theme.mutedForeground)
                .padding(.top, 6)
            FlowLayout(spacing: 8) {
                ForEach(model.choiceOptions, id: \.self) { choice in
                    Button(choice) { model.recordChoice(choice) }
                        .buttonStyle(PillButtonStyle())
                }
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.border))
        .shadow(color: .black.opacity(0.6), radius: 20, y: 12)
        .foregroundStyle(Theme.foreground)
    }
}

struct ToastView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.border))
            .foregroundStyle(Theme.foreground)
    }
}

/// Wrapping row of pills.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width && !row.indices.isEmpty {
                let y = row.y + row.height + spacing
                rows.append(Row(indices: [i], y: y, width: size.width, height: size.height))
                continue
            }
            row.indices.append(i)
            row.width = needed
            row.height = max(row.height, size.height)
            rows[rows.count - 1] = row
        }
        return rows
    }
}
