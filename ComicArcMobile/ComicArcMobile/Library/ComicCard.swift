import SwiftUI

struct ComicCard: View {
    let comic: Comic

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover — full-bleed, clipped by parent arcCard cornerRadius at the top.
            // Matches macOS .comic-card layout: cover fills card, info section below.
            ZStack(alignment: .topTrailing) {
                CoverImage(comic: comic)
                    .aspectRatio(2/3, contentMode: .fill)
                    .clipped()

                // Status badge (top-right): finished > favorite
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
            // Progress bar sits at bottom of cover area
            .overlay(alignment: .bottom) {
                if comic.pageCount > 0 && comic.progress > 0 {
                    Rectangle()
                        .fill(comic.isFinished ? Color.green : Color.arcGold)
                        .frame(height: 3)
                        .scaleEffect(x: min(1, comic.progressPercent), y: 1, anchor: .leading)
                }
            }

            // Info section — matches macOS .card-info padding
            VStack(alignment: .leading, spacing: 4) {
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
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .arcCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var parts: [String] = [comic.title]
        if comic.publisher != "Unknown" { parts.append(comic.publisher) }
        if comic.isFinished {
            parts.append("Finished")
        } else if comic.isStarted, comic.pageCount > 0 {
            parts.append("Page \(comic.progress + 1) of \(comic.pageCount)")
        } else {
            parts.append("Unread")
        }
        if comic.rating > 0 { parts.append("\(comic.rating) star\(comic.rating == 1 ? "" : "s")") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Cover Image

struct CoverImage: View {
    private enum Source { case comic(Comic); case id(Int64) }
    private let source: Source

    /// Fast path — use when the full Comic struct is available. Skips the DB lookup.
    init(comic: Comic) { source = .comic(comic) }
    /// Fallback path — use only when no Comic struct is available (e.g. series cover by id).
    init(comicId: Int64) { source = .id(comicId) }

    @State private var image: UIImage?

    private var stableId: Int64 {
        switch source { case .comic(let c): return c.id; case .id(let i): return i }
    }

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.arcCard
                    .overlay {
                        Image(systemName: "book.closed")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .accessibilityHidden(true)
        .task(id: stableId) {
            switch source {
            case .comic(let c): image = await ThumbnailCache.shared.thumbnail(comic: c)
            case .id(let i):    image = await ThumbnailCache.shared.thumbnail(comicId: i)
            }
        }
    }
}
