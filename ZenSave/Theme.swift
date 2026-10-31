import SwiftUI

/// Colors from the web prototype's design tokens (src/styles.css), converted from oklch to sRGB.
enum Theme {
    static let background = Color(hex: 0x08120C)
    static let card = Color(hex: 0x101E17)
    static let foreground = Color(hex: 0xF2F3E4)
    static let primary = Color(hex: 0xBBEC4C)
    static let primaryForeground = Color(hex: 0x08120C)
    static let muted = Color(hex: 0x1E2D25)
    static let mutedForeground = Color(hex: 0x9BAA98)
    static let destructive = Color(hex: 0xFE6652)
    static let border = Color.white.opacity(0.09)
    static let radius: CGFloat = 20

    /// The prototype uses Instrument Serif for display text. Until the font is bundled
    /// (see README), the system serif (New York) stands in.
    static func display(_ size: CGFloat) -> Font {
        if UIFont(name: "InstrumentSerif-Regular", size: size) != nil {
            return .custom("InstrumentSerif-Regular", size: size)
        }
        return .system(size: size, design: .serif)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// `.card-surface` from the prototype.
struct CardSurface: ViewModifier {
    var highlighted = false
    func body(content: Content) -> some View {
        content
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(highlighted ? Theme.primary : Theme.border, lineWidth: highlighted ? 2 : 1)
            )
    }
}

extension View {
    func cardSurface(highlighted: Bool = false) -> some View {
        modifier(CardSurface(highlighted: highlighted))
    }
}

/// `.pill` / `.pill-active` from the prototype.
struct PillButtonStyle: ButtonStyle {
    var active = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(active ? Theme.primaryForeground : Theme.foreground)
            .background(active ? Theme.primary : Theme.muted, in: Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Small uppercase eyebrow label ("UNSCROLL", "RECENT").
struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption)
            .tracking(2.4)
            .foregroundStyle(Theme.mutedForeground)
    }
}
