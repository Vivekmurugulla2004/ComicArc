import SwiftUI

struct ContentView: View {
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular {
            iPadLayout
        } else {
            iPhoneLayout
        }
    }

    // MARK: - iPhone (tab bar)

    private var iPhoneLayout: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library",     systemImage: "books.vertical") }
            RunsView()
                .tabItem { Label("Runs",        systemImage: "list.number") }
            FavoritesView()
                .tabItem { Label("Favorites",   systemImage: "heart") }
            ReadingListView()
                .tabItem { Label("Want to Read",systemImage: "bookmark") }
            SettingsView()
                .tabItem { Label("Settings",    systemImage: "gear") }
        }
        .tint(.arcGold)
        .background(Color.arcBg.ignoresSafeArea())
    }

    // MARK: - iPad (sidebar)

    @State private var iPadSelection: SidebarTab? = .library

    private var iPadLayout: some View {
        NavigationSplitView {
            List(selection: $iPadSelection) {
                ForEach(SidebarTab.allCases) { tab in
                    Label(tab.label, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .navigationTitle("ComicArc")
            .listStyle(.sidebar)
        } detail: {
            switch iPadSelection ?? .library {
            case .library:     LibraryView()
            case .runs:        RunsView()
            case .favorites:   FavoritesView()
            case .readingList: ReadingListView()
            case .stats:       StatsView()
            case .settings:    SettingsView()
            }
        }
        .tint(.arcGold)
    }
}

// MARK: - Sidebar tabs

enum SidebarTab: String, CaseIterable, Identifiable, Hashable {
    case library, runs, favorites, readingList, stats, settings
    var id: String { rawValue }

    var label: String {
        switch self {
        case .library:     return "Library"
        case .runs:        return "Reading Runs"
        case .favorites:   return "Favorites"
        case .readingList: return "Want to Read"
        case .stats:       return "Stats"
        case .settings:    return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .library:     return "books.vertical"
        case .runs:        return "list.number"
        case .favorites:   return "heart"
        case .readingList: return "bookmark"
        case .stats:       return "chart.bar"
        case .settings:    return "gear"
        }
    }
}
