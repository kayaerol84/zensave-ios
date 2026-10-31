import SwiftUI

struct LimitsView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: TrackedApp?
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.mode == .screenTime
                 ? "Pick each app in Screen Time and set a daily limit. You'll get a nudge when you reach it."
                 : "Set a daily limit for each app. Long-press to rename or remove.")
                .font(.subheadline)
                .foregroundStyle(Theme.mutedForeground)

            ForEach(model.apps) { app in
                LimitRow(app: app)
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") { editing = app }
                        Button("Remove", systemImage: "trash", role: .destructive) { model.removeApp(app.id) }
                    }
            }

            Button {
                adding = true
            } label: {
                Label("Track another app", systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(16)
            }
            .foregroundStyle(Theme.primary)
            .cardSurface()

            if model.mode == .screenTime {
                Button("Switch back to demo mode") { model.useDemoMode() }
                    .font(.footnote)
                    .underline()
                    .foregroundStyle(Theme.mutedForeground)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
        .sheet(item: $editing) { app in
            NameEmojiSheet(title: "Rename", name: app.name, emoji: app.emoji) { name, emoji in
                model.rename(app.id, name: name, emoji: emoji)
            }
        }
        .sheet(isPresented: $adding) {
            NameEmojiSheet(title: "Track an app", name: "", emoji: "") { name, emoji in
                model.addApp(name: name, emoji: emoji)
            }
        }
    }
}

private struct LimitRow: View {
    @Environment(AppModel.self) private var model
    let app: TrackedApp

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("\(app.emoji) \(app.name)").font(.body.weight(.semibold))
                Spacer()
                Text(Nudge.formatMinutes(app.limit)).font(.body.weight(.semibold)).foregroundStyle(Theme.primary)
                if model.mode == .screenTime {
                    AppPickerButton(appID: app.id)
                }
            }
            Slider(
                value: Binding(
                    get: { Double(app.limit) },
                    set: { model.setLimit(Int($0), for: app.id) }
                ),
                in: 5...120,
                step: 5,
                onEditingChanged: { editing in
                    if !editing { model.saveApps() }
                }
            )
            .tint(Theme.primary)
        }
        .padding(16)
        .cardSurface()
    }
}

/// Small form for a name + emoji, used for tracked apps and alternatives.
struct NameEmojiSheet: View {
    let title: String
    @State var name: String
    @State var emoji: String
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Emoji", text: $emoji)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name.trimmingCharacters(in: .whitespaces), String(emoji.prefix(1)))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
