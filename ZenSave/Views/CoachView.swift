import SwiftUI

struct CoachView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 16) {
            Text("Tell us about you, and AI will pick a fitting alternative when you hit a limit.")
                .font(.subheadline)
                .foregroundStyle(Theme.mutedForeground)

            field("Your goals", "e.g. read 20 books this year, get stronger", $model.profile.goals)
            field("Time you usually have", "e.g. 15 min on weekdays, an hour at weekends", $model.profile.availableTime)
            field("Activities you enjoy", "e.g. running, Imprint, guitar, calling friends", $model.profile.activities)

            Toggle(isOn: $model.profile.useAI) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI suggestions").font(.body.weight(.semibold))
                    Text(SuggestionService.isAvailable
                         ? "Runs on your iPhone with Apple Intelligence. Nothing leaves your device."
                         : "Needs an iPhone with Apple Intelligence (iOS 26+). Until then you'll get the standard nudge.")
                        .font(.caption)
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            .tint(Theme.primary)
            .padding(16)
            .cardSurface(highlighted: model.profile.useAI)
        }
    }

    private func field(_ label: String, _ placeholder: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline.weight(.semibold))
            TextField(placeholder, text: text, axis: .vertical)
                .lineLimit(2...4)
                .padding(10)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.12)))
        }
        .padding(16)
        .cardSurface()
    }
}
