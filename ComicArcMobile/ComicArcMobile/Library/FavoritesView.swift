import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var comics: [Comic] = []
    @State private var detailComicId: Int64?

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .regular ? 160 : 140), spacing: 12)]
    }
    private let db = DatabaseManager.shared

    var body: some View {
        NavigationStack {
            Group {
                if comics.isEmpty {
                    EmptyStateView(
                        icon: "heart",
                        title: "No Favorites",
                        message: "Open any comic's detail page and tap the heart to add it here."
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(comics) { comic in
                                ComicCard(comic: comic)
                                    .onTapGesture { detailComicId = comic.id }
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Favorites")
            .background(Color.arcBg)
            .onAppear { load() }
            .sheet(item: Binding(
                get: { detailComicId.map { ComicSheetID(id: $0) } },
                set: { detailComicId = $0?.id }
            )) { wrapper in
                ComicDetailView(comicId: wrapper.id)
                    .environmentObject(library)
                    .onDisappear { load() }
            }
        }
    }

    private func load() {
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                DatabaseManager.shared.allComics(favoritesOnly: true)
            }.value
            comics = result
        }
    }
}

