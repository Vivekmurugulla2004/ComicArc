import SwiftUI

// MARK: - ComicArc Design System
// Matches the macOS app's CSS color palette

extension Color {
    // Core palette
    static let arcGold    = Color(red: 247/255, green: 201/255, blue: 72/255)   // #f7c948
    static let arcRed     = Color(red: 239/255, green: 35/255,  blue: 60/255)   // #ef233c
    static let arcBg      = Color(red: 11/255,  green: 12/255,  blue: 24/255)   // #0b0c18
    static let arcSurface = Color(red: 19/255,  green: 21/255,  blue: 42/255)   // #13152a
    static let arcCard    = Color(red: 26/255,  green: 29/255,  blue: 53/255)   // #1a1d35
    static let arcBorder  = Color(red: 45/255,  green: 49/255,  blue: 88/255)   // #2d3158
    static let arcMuted   = Color(red: 122/255, green: 122/255, blue: 154/255)  // #7a7a9a

    // Publisher badge colors
    static let pubMarvel  = Color(red: 0.8, green: 0,    blue: 0)
    static let pubDC      = Color(red: 0.1, green: 0.23, blue: 0.54)
    static let pubImage   = Color(red: 0.7, green: 0.28, blue: 0)
    static let pubManga   = Color(red: 0.42, green: 0.05, blue: 0.68)
    static let pubIndie   = Color(red: 0.1, green: 0.42, blue: 0.23)
}

// MARK: - Design Tokens

extension CGFloat {
    /// Matches macOS CSS `--radius: 12px`
    static let arcCardRadius: CGFloat  = 12
    /// Inner elements (cover images within cards)
    static let arcInnerRadius: CGFloat = 8
    /// Publisher/status badge corner radius — matches macOS `border-radius: 4px`
    static let arcBadgeRadius: CGFloat = 4
}

// MARK: - Arc Card Style Modifier
// Consolidates the repeating pattern: arcCard background + clip + 1pt border.
// Matches macOS `.comic-card` / `.series-card` styling.

private struct ArcCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    func body(content: Content) -> some View {
        content
            .background(Color.arcCard)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.arcBorder, lineWidth: 1)
            )
    }
}

extension View {
    func arcCard(cornerRadius: CGFloat = .arcCardRadius) -> some View {
        modifier(ArcCardModifier(cornerRadius: cornerRadius))
    }
}

// MARK: - Filter Chip
// Single component for all horizontal filter bars (publisher, tag, smart filter).
// Two visual styles mirror the macOS tab hierarchy:
//   .filled  — primary filter (publisher/tag): solid gold when active, matches `.tab.active`
//   .outlined — secondary filter (smart filters): gold-tinted outline when active

struct FilterChip: View {
    enum Style { case filled, outlined }

    let label: String
    let isActive: Bool
    var style: Style = .filled
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(chipBackground)
                .foregroundStyle(chipForeground)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(chipBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var chipBackground: Color {
        switch (style, isActive) {
        case (.filled, true):   return .arcGold
        case (.outlined, true): return Color.arcGold.opacity(0.15)
        default:                return .arcSurface
        }
    }

    private var chipForeground: Color {
        switch (style, isActive) {
        case (.filled, true):   return .arcBg         // matches macOS: #0b0c18 on gold
        case (.outlined, true): return .arcGold
        default:                return Color.primary
        }
    }

    private var chipBorder: Color {
        switch (style, isActive) {
        case (.filled, true):   return .clear
        case (.outlined, true): return .arcGold
        default:                return .arcBorder
        }
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 52))
                .foregroundStyle(Color.arcMuted)
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.arcMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline)
                        .padding(.horizontal, 28).padding(.vertical, 12)
                        .background(Color.arcGold)
                        .foregroundStyle(Color.arcBg)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.top, 4)
                .accessibilityLabel(actionTitle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Publisher badge helper

struct PublisherBadge: View {
    let publisher: String

    var body: some View {
        Text(publisher.uppercased())
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: .arcBadgeRadius))
    }

    private var badgeColor: Color {
        let p = publisher.lowercased()
        if p.contains("marvel")      { return .pubMarvel }
        if p.contains("dc")          { return .pubDC }
        if p.contains("image")       { return .pubImage }
        if p.contains("manga") || p.contains("viz") || p.contains("shonen") { return .pubManga }
        if p.contains("dark horse") || p.contains("idw") || p.contains("boom") { return .pubIndie }
        return .arcMuted
    }
}
