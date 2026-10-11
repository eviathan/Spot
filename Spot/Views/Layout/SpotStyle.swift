//
//  SpotStyle.swift
//  Spot
//

import SwiftUI

/// The colours and pieces the panels share (Settings, the Library's detail): dark cards on the navy page, white
/// text, blue-grey for headings and notes, the transport's green for actions.
enum SpotStyle {
    /// The page (as behind the tab and the Library).
    static let page = Color(hue: 0.62, saturation: 0.38, brightness: 0.24)
    /// A panel or card on it (as the Library's menu).
    static let card = Color(hue: 0.63, saturation: 0.30, brightness: 0.19)
    /// A control's fill on a card.
    static let control = Color.white.opacity(0.08)
    /// Headings and notes (as the dimmed footer icons, a little lighter to read as text).
    static let secondary = Color(hue: 0.62, saturation: 0.22, brightness: 0.70)
    static let divider = Color.white.opacity(0.07)
    static let border = Color.white.opacity(0.06)
    /// As the play button while playing.
    static let accent = Color(red: 0.55, green: 0.85, blue: 0.45)
}

/// A small capitalised heading over a card or a group.
struct SpotHeading: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(SpotStyle.secondary)
    }
}

/// A quiet rounded button for a card: white text on a faint fill (red text for destructive ones).
struct SpotPillButtonStyle: ButtonStyle {
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isDestructive ? Color(red: 1, green: 0.5, blue: 0.5) : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.16 : 0.08)))
            .contentShape(Capsule())
    }
}

extension View {
    /// A card: the darker panel colour, rounded, with a faint edge.
    func spotCard(padding: CGFloat = 14) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(SpotStyle.border))
    }
}
