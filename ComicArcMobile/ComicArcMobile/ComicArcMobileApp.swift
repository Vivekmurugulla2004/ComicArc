import SwiftUI

// #0b0c18 arcBg, #13152a arcSurface
private let arcBgUIColor      = UIColor(red: 11/255,  green: 12/255,  blue: 24/255,  alpha: 1)
private let arcSurfaceUIColor = UIColor(red: 19/255,  green: 21/255,  blue: 42/255,  alpha: 1)
private let arcBorderUIColor  = UIColor(red: 45/255,  green: 49/255,  blue: 88/255,  alpha: 1)
private let arcGoldUIColor    = UIColor(red: 247/255, green: 201/255, blue: 72/255,  alpha: 1)

@main
struct ComicArcMobileApp: App {
    @StateObject private var library = LibraryViewModel()
    @AppStorage("onboardingDone") private var onboardingDone = false

    init() {
        // Tab bar
        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = arcSurfaceUIColor
        tab.stackedLayoutAppearance.selected.iconColor = arcGoldUIColor
        tab.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: arcGoldUIColor]
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        // Navigation bar
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = arcSurfaceUIColor
        nav.titleTextAttributes = [.foregroundColor: UIColor.white]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        // Table / List background
        UITableView.appearance().backgroundColor = arcBgUIColor

        // Collection view (used by some grids)
        UICollectionView.appearance().backgroundColor = arcBgUIColor
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if onboardingDone {
                    ContentView()
                } else {
                    OnboardingView()
                }
            }
            .environmentObject(library)
            .preferredColorScheme(.dark)
            .tint(.arcGold)
            .background(Color.arcBg.ignoresSafeArea())
            .onOpenURL { url in
                onboardingDone = true
                library.importFiles([url])
            }
        }
    }
}
