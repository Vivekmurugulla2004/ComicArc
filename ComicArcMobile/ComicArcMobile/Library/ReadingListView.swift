import SwiftUI

struct ReadingListView: View {
    @EnvironmentObject var library: LibraryViewModel
    var body: some View {
        ComicCollectionView(
            title: "Want to Read",
            emptyIcon: "bookmark",
            emptyTitle: "Reading List Empty",
            emptyMessage: "Open any comic's detail page and tap Want to Read.",
            loader: { DatabaseManager.shared.allComics(readingListOnly: true) }
        )
        .environmentObject(library)
    }
}
