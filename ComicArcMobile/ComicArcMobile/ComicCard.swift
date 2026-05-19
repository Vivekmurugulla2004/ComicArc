import SwiftUI

struct ComicCard: View {
    @EnvironmentObject var library: LibraryViewModel
    let comic: Comic

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottom) {
                CoverImage(comic: comic)
                    .aspectRatio(2/3, contentMode: .fill)
                    .clipped()
                if comic.pageCount > 0 {
                    ArcProgressBar(value: comic.progress)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: .arcInnerRadius))
            .overlay(alignment: .topTrailing) {
                if comic.isFavorite {
                    CardBadge(systemImage: "heart.fill", color: .arcRed)
                        .padding(4)
                }
            }
            .overlay(alignment: .topLeading) {
                if comic.inReadingList {
                    CardBadge(systemImage: "bookmark.fill", color: .arcGold)
                        .padding(4)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(comic.title)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let issue = comic.issueNumber {
                    Text("#\(issue)")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.arcMuted)
                }
                PublisherBadge(publisher: comic.publisher)
                    .padding(.top, 2)
            }
            .padding(.horizontal, .arcS6)
            .padding(.vertical, .arcS6)
        }
        .arcCard()
        .buttonStyle(ArcCardButtonStyle())
    }
}

struct CoverImage: View {
    @EnvironmentObject var library: LibraryViewModel
    let comic: Comic
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.arcSurface
                    Image(systemName: "book.closed.fill")
                        .font(.largeTitle)
                        .foregroundStyle(Color.arcBorder)
                }
            }
        }
        .task(id: comic.id) { await loadCover() }
    }

    private func loadCover() async {
        guard image == nil else { return }
        image = await Task.detached(priority: .background) {
            guard let url = library.resolvedURL(for: comic) else { return UIImage?.none }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            return ComicReader.page(url: url, index: 0)
        }.value
    }
}
