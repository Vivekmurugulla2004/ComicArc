import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject var library: LibraryViewModel
    var body: some View {
        ComicCollectionView(
            title: "Favorites",
            emptyIcon: "heart",
            emptyTitle: "No Favorites",
            emptyMessage: "Open any comic's detail page and tap the heart to add it here.",
            loader: { DatabaseManager.shared.allComics(favoritesOnly: true) }
        )
        .environmentObject(library)
    }
}
