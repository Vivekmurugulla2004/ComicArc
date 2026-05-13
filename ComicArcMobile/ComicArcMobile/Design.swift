import SwiftUI

// MARK: - ComicArc Design System
// Matches the macOS app's CSS color palette

extension Color {
    // Core palette
    static let arcGold    = Color(red: 247/255, green: 201/255, blue: 72/255)   // #f7c948
    static let arcGold2   = Color(red: 255/255, green: 224/255, blue: 130/255)  // #ffe082
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

// MARK: - Empty state

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

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
            .clipShape(RoundedRectangle(cornerRadius: 3))
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
