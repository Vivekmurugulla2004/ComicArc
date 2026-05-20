import SwiftUI

extension Color {
    static let arcGold      = Color(red: 247/255, green: 201/255, blue: 72/255)
    static let arcGold2     = Color(red: 255/255, green: 224/255, blue: 130/255)
    static let arcRed       = Color(red: 239/255, green: 35/255,  blue: 60/255)
    static let arcRed2      = Color(red: 255/255, green: 107/255, blue: 129/255)
    static let arcBg        = Color(red: 11/255,  green: 12/255,  blue: 24/255)
    static let arcSurface   = Color(red: 19/255,  green: 21/255,  blue: 42/255)
    static let arcCard      = Color(red: 26/255,  green: 29/255,  blue: 53/255)
    static let arcCardHover = Color(red: 33/255,  green: 37/255,  blue: 74/255)
    static let arcBorder    = Color(red: 45/255,  green: 49/255,  blue: 88/255)
    static let arcMuted     = Color(red: 122/255, green: 122/255, blue: 154/255)
    static let arcBlue      = Color(red: 37/255,  green: 99/255,  blue: 235/255)

    static let pubMarvel  = Color(red: 0.8,  green: 0,    blue: 0)
    static let pubDC      = Color(red: 0.1,  green: 0.23, blue: 0.54)
    static let pubImage   = Color(red: 0.7,  green: 0.28, blue: 0)
    static let pubManga   = Color(red: 0.42, green: 0.05, blue: 0.68)
    static let pubIndie   = Color(red: 0.1,  green: 0.42, blue: 0.23)
}

extension CGFloat {
    static let arcCardRadius: CGFloat  = 12
    static let arcInnerRadius: CGFloat = 8
    static let arcBadgeRadius: CGFloat = 4

    static let arcS2:  CGFloat = 2
    static let arcS4:  CGFloat = 4
    static let arcS6:  CGFloat = 6
    static let arcS8:  CGFloat = 8
    static let arcS10: CGFloat = 10
    static let arcS12: CGFloat = 12
    static let arcS16: CGFloat = 16
    static let arcS20: CGFloat = 20
    static let arcS24: CGFloat = 24
    static let arcS32: CGFloat = 32
}

extension Animation {
    static let arcSnappy = Animation.easeInOut(duration: 0.2)
    static let arcFast   = Animation.easeInOut(duration: 0.15)
    static let arcSpring = Animation.spring(response: 0.3, dampingFraction: 0.8)
}

private struct ArcCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    func body(content: Content) -> some View {
        content
            .background(Color.arcCard)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.arcBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.28), radius: 4, x: 0, y: 2)
    }
}

extension View {
    func arcCard(cornerRadius: CGFloat = .arcCardRadius) -> some View {
        modifier(ArcCardModifier(cornerRadius: cornerRadius))
    }
}

struct ArcCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .animation(.arcFast, value: configuration.isPressed)
    }
}

struct ArcProgressBar: View {
    let value: Double
    var height: CGFloat = 3
    var color: Color = .arcGold

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.arcBorder)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * min(1, max(0, value)))
                }
        }
        .frame(height: height)
    }
}

struct CardBadge: View {
    let systemImage: String
    let color: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption)
            .foregroundStyle(color)
            .padding(5)
            .background(.ultraThinMaterial, in: Circle())
    }
}

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
                .padding(.horizontal, .arcS12).padding(.vertical, .arcS6)
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
        case (.filled, true): return .arcBg
        case (.outlined, true): return .arcGold
        default: return Color.primary
        }
    }

    private var chipBorder: Color {
        switch (style, isActive) {
        case (.filled, true): return .clear
        case (.outlined, true): return .arcGold
        default: return .arcBorder
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: .arcS16) {
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
                .padding(.horizontal, .arcS32)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.headline)
                        .padding(.horizontal, 28).padding(.vertical, .arcS12)
                        .background(Color.arcGold)
                        .foregroundStyle(Color.arcBg)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .padding(.top, .arcS4)
                .accessibilityLabel(actionTitle)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 60)
    }
}

struct ComicCollectionView: View {
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    let title: String
    let emptyIcon: String
    let emptyTitle: String
    let emptyMessage: String
    let loader: @Sendable () -> [Comic]

    @State private var comics: [Comic] = []
    @State private var detailComic: Comic?

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .regular ? 160 : 140), spacing: .arcS12)]
    }

    var body: some View {
        NavigationStack {
            Group {
                if comics.isEmpty {
                    EmptyStateView(icon: emptyIcon, title: emptyTitle, message: emptyMessage)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: .arcS16) {
                            ForEach(comics) { comic in
                                ComicCard(comic: comic)
                                    .onTapGesture { detailComic = comic }
                            }
                        }
                        .padding(.arcS16)
                    }
                }
            }
            .navigationTitle(title)
            .background(Color.arcBg)
            .onAppear { load() }
            .sheet(item: $detailComic) { comic in
                ComicDetailView(comic: comic)
                    .environmentObject(library)
            }
        }
    }

    private func load() {
        let fn = loader
        Task {
            let result = await Task.detached(priority: .userInitiated, operation: fn).value
            comics = result
        }
    }
}

struct PublisherBadge: View {
    let publisher: String

    var body: some View {
        Text(publisher.uppercased())
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, .arcS6)
            .padding(.vertical, 2)
            .background(badgeColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: .arcBadgeRadius))
    }

    private var badgeColor: Color {
        let p = publisher.lowercased()
        if p.contains("marvel")  { return .pubMarvel }
        if p.contains("dc")      { return .pubDC }
        if p.contains("image")   { return .pubImage }
        if p.contains("manga") || p.contains("viz") || p.contains("shonen") { return .pubManga }
        if p.contains("dark horse") || p.contains("idw") || p.contains("boom") { return .pubIndie }
        return .arcMuted
    }
}
