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

    private var iPhoneLayout: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Library",     systemImage: "books.vertical") }
            RunsView()
                .tabItem { Label("Runs",        systemImage: "list.number") }
            CollectionsView()
                .tabItem { Label("Collections", systemImage: "folder") }
            FavoritesView()
                .tabItem { Label("Favorites",   systemImage: "heart") }
            ReadingListView()
                .tabItem { Label("Want to Read",systemImage: "bookmark") }
            StatsView()
                .tabItem { Label("Stats",       systemImage: "chart.bar") }
            TagsView()
                .tabItem { Label("Tags",        systemImage: "tag") }
            TrashView()
                .tabItem { Label("Trash",       systemImage: "trash") }
            SettingsView()
                .tabItem { Label("Settings",    systemImage: "gear") }
        }
        .tint(.arcGold)
        .background(Color.arcBg.ignoresSafeArea())
        .onAppear { library.loadCollections() }
    }

    @State private var iPadSelection: SidebarTab? = .library

    private var iPadLayout: some View {
        NavigationSplitView {
            List(selection: $iPadSelection) {
                ForEach(SidebarTab.allCases) { tab in
                    Label(tab.label, systemImage: tab.icon).tag(tab)
                }
            }
            .navigationTitle("ComicArc")
            .listStyle(.sidebar)
        } detail: {
            switch iPadSelection ?? .library {
            case .library:      LibraryView()
            case .runs:         RunsView()
            case .collections:  CollectionsView()
            case .favorites:    FavoritesView()
            case .readingList:  ReadingListView()
            case .stats:        StatsView()
            case .tags:         TagsView()
            case .trash:        TrashView()
            case .settings:     SettingsView()
            }
        }
        .tint(.arcGold)
        .onAppear { library.loadCollections() }
    }
}

enum SidebarTab: String, CaseIterable, Identifiable, Hashable {
    case library, runs, collections, favorites, readingList, stats, tags, trash, settings
    var id: String { rawValue }

    var label: String {
        switch self {
        case .library:     return "Library"
        case .runs:        return "Reading Runs"
        case .collections: return "Collections"
        case .favorites:   return "Favorites"
        case .readingList: return "Want to Read"
        case .stats:       return "Stats"
        case .tags:        return "Tags"
        case .trash:       return "Trash"
        case .settings:    return "Settings"
        }
    }

    var icon: String {
        switch self {
        case .library:     return "books.vertical"
        case .runs:        return "list.number"
        case .collections: return "folder"
        case .favorites:   return "heart"
        case .readingList: return "bookmark"
        case .stats:       return "chart.bar"
        case .tags:        return "tag"
        case .trash:       return "trash"
        case .settings:    return "gear"
        }
    }
}
