import SwiftUI

struct ComicCard: View {
    let comic: Comic

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                CoverImage(comicId: comic.id)
                    .aspectRatio(2/3, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(alignment: .bottom) {
                        if comic.pageCount > 0 && comic.progress > 0 {
                            GeometryReader { geo in
                                Rectangle()
                                    .fill(comic.isFinished ? Color.green : Color.arcGold)
                                    .frame(width: geo.size.width * comic.progressPercent, height: 4)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            }
                        }
                    }

                // Status badges (top-right stack)
                VStack(spacing: 4) {
                    if comic.isFinished {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .padding(5)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(4)
                    } else if comic.isFavorite {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(Color.arcRed)
                            .padding(5)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(4)
                    }
                }
            }

            Text(comic.title)
                .font(.caption).fontWeight(.medium)
                .foregroundStyle(.white)
                .lineLimit(2)

            PublisherBadge(publisher: comic.publisher)

            if comic.rating > 0 {
                HStack(spacing: 2) {
                    ForEach(1...5, id: \.self) { i in
                        Image(systemName: i <= comic.rating ? "star.fill" : "star")
                            .font(.system(size: 8))
                            .foregroundStyle(i <= comic.rating ? Color.arcGold : Color.arcMuted)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.arcCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.arcBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var parts: [String] = [comic.title]
        if comic.publisher != "Unknown" { parts.append(comic.publisher) }
        if comic.isFinished {
            parts.append("Finished")
        } else if comic.isStarted, comic.pageCount > 0 {
            parts.append("Page \(comic.progress) of \(comic.pageCount)")
        } else {
            parts.append("Unread")
        }
        if comic.rating > 0 { parts.append("\(comic.rating) star\(comic.rating == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Cover Image

struct CoverImage: View {
    let comicId: Int64
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.arcCard)
                    .overlay {
                        Image(systemName: "book.closed")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .accessibilityHidden(true)
        .task(id: comicId) { image = await ThumbnailCache.shared.thumbnail(comicId: comicId) }
    }
}
