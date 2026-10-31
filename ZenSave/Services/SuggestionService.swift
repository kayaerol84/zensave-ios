import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Personalised "switch to…" suggestions.
///
/// The web prototype called an OpenAI model through a server function. On iPhone the
/// equivalent with no API key, no server and no data leaving the device is Apple's
/// on-device Foundation Models framework (iOS 26+, Apple Intelligence devices).
/// On anything else this returns nil and the rule-based message is used.
enum SuggestionService {
    static let instructions = """
    You are Unscroll, a kind habit coach. The user just hit their scrolling limit. \
    Suggest ONE concrete alternative activity that fits their goals, available time and preferred activities. \
    Reply in max 2 short sentences, starting with 'You spent X in APP' then the suggestion. No emojis, no lists.
    """

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    static func prompt(appName: String, minutes: Int, profile: CoachProfile) -> String {
        func orNotGiven(_ s: String) -> String { s.isEmpty ? "not given" : s }
        return """
        App: \(appName)
        Time spent: \(minutes) minutes
        Goals: \(orNotGiven(profile.goals))
        Available time now: \(orNotGiven(profile.availableTime))
        Preferred activities: \(orNotGiven(profile.activities))
        """
    }

    /// Returns a suggestion, or nil when AI is off, the profile is empty or the model is unavailable.
    static func suggest(appName: String, minutes: Int, profile: CoachProfile) async -> String? {
        guard profile.useAI, !profile.isEmpty else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), SystemLanguageModel.default.isAvailable {
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt(appName: appName, minutes: minutes, profile: profile))
                let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : text
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}
