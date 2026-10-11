//
//  SpotStyle.swift
//  Spot
//

import SwiftUI

/// The colours and pieces the panels share (Settings, the Library's detail): dark cards on the navy page, white
/// text, blue-grey for headings and notes, the transport's green for actions.
/// From the theme in use (read in a view's body, so views redraw when it changes).
enum SpotStyle {
    private static var theme: Theme { ThemeStore.shared.current }

    /// The page (as behind the tab and the Library).
    static var page: Color { theme.page }
    /// A panel or card on it (as the Library's menu).
    static var card: Color { theme.card }
    /// A control's fill on a card.
    static var control: Color { theme.control }
    /// Headings and notes (as the dimmed footer icons, a little lighter to read as text).
    static var secondary: Color { theme.secondaryText }
    static var divider: Color { theme.divider }
    static var border: Color { theme.border }
    /// As the play button while playing.
    static var accent: Color { theme.accent }
    static var text: Color { theme.text }
    static var dimmed: Color { theme.dimmed }
    static var warning: Color { theme.warning }
    static var error: Color { theme.error }
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
            .foregroundStyle(isDestructive ? SpotStyle.error : SpotStyle.text)
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
