import SwiftUI

struct SwitchView: View {
    @Environment(AppModel.self) private var model
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick what we suggest when you hit a limit.")
                .font(.subheadline)
                .foregroundStyle(Theme.mutedForeground)

            ForEach(model.alternatives) { alt in
                Button { model.toggleAlternative(alt.id) } label: {
                    HStack(spacing: 12) {
                        Text(alt.emoji).font(.title)
                        Text(alt.name.prefix(1).uppercased() + alt.name.dropFirst())
                            .font(.body.weight(.semibold))
                        Spacer()
                        Text(alt.enabled ? "On" : "Off")
                            .foregroundStyle(alt.enabled ? Theme.primary : Theme.mutedForeground)
                    }
                    .padding(16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .cardSurface(highlighted: alt.enabled)
            }

            Button {
                adding = true
            } label: {
                Label("Add an alternative", systemImage: "plus")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(16)
            }
            .foregroundStyle(Theme.primary)
            .cardSurface()
        }
        .sheet(isPresented: $adding) {
            NameEmojiSheet(title: "New alternative", name: "", emoji: "") { name, emoji in
                model.addAlternative(name: name, emoji: emoji)
            }
        }
    }
}
