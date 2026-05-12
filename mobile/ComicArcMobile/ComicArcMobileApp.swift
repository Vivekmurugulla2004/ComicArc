import SwiftUI

@main
struct ComicArcMobileApp: App {
    @StateObject private var library = LibraryViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                // Handle "Open with ComicArc" from Files / Mail / Safari
                .onOpenURL { url in
                    library.importFiles([url])
                }
        }
    }
}
