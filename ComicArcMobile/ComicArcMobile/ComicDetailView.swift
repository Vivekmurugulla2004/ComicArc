import SwiftUI

struct ComicDetailView: View {
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    var comic: Comic { library.comics.first { $0.id == _comic.id } ?? _comic }
    private let _comic: Comic

    @State private var showReader = false
    @State private var hoverRating = 0

    init(comic: Comic) { self._comic = comic }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.arcBg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: .arcS24) {
                        coverSection
                        infoSection
                        actionsSection
                        creditsSection
                        progressSection
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showReader) {
                if let url = library.resolvedURL(for: comic) {
                    ReaderView(comic: comic, url: url)
                        .environmentObject(library)
                }
            }
        }
    }

    private var coverSection: some View {
        CoverImage(comic: comic)
            .frame(width: 180, height: 270)
            .clipShape(RoundedRectangle(cornerRadius: .arcCardRadius))
            .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 6)
            .padding(.top, .arcS24)
    }

    private var infoSection: some View {
        VStack(spacing: .arcS8) {
            Text(comic.title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            HStack(spacing: .arcS8) {
                PublisherBadge(publisher: comic.publisher)
                if let issue = comic.issueNumber {
                    Text("#\(issue)")
                        .font(.caption)
                        .foregroundStyle(Color.arcMuted)
                }
                if let year = comic.year {
                    Text(String(year))
                        .font(.caption)
                        .foregroundStyle(Color.arcMuted)
                }
            }
            starRating
        }
        .padding(.horizontal, .arcS24)
    }

    private var starRating: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: i <= (hoverRating > 0 ? hoverRating : comic.rating) ? "star.fill" : "star")
                    .foregroundStyle(i <= comic.rating ? Color.arcGold : Color.arcBorder)
                    .onTapGesture { library.rate(id: comic.id, rating: i) }
            }
        }
        .font(.title3)
    }

    private var actionsSection: some View {
        VStack(spacing: .arcS12) {
            Button {
                showReader = true
            } label: {
                Label(comic.currentPage > 0 && !comic.isFinished ? "Resume Reading" : "Read",
                      systemImage: "book.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.arcGold)
                    .foregroundStyle(Color.arcBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            HStack(spacing: .arcS12) {
                toggleButton(
                    label: comic.isFavorite ? "Favorited" : "Favorite",
                    icon: comic.isFavorite ? "heart.fill" : "heart",
                    active: comic.isFavorite
                ) { library.toggleFavorite(id: comic.id) }

                toggleButton(
                    label: comic.inReadingList ? "In List" : "Want to Read",
                    icon: comic.inReadingList ? "bookmark.fill" : "bookmark",
                    active: comic.inReadingList
                ) { library.toggleReadingList(id: comic.id) }
            }
            HStack(spacing: .arcS12) {
                if !comic.isFinished {
                    outlineButton(label: "Mark as Read", icon: "checkmark") {
                        library.markRead(id: comic.id)
                    }
                } else {
                    outlineButton(label: "Mark Unread", icon: "arrow.counterclockwise") {
                        library.markUnread(id: comic.id)
                    }
                }
            }
        }
        .padding(.horizontal, .arcS24)
    }

    @ViewBuilder
    private var creditsSection: some View {
        if comic.writer != nil || comic.penciller != nil || comic.storyArc != nil {
            VStack(alignment: .leading, spacing: .arcS8) {
                Text("Credits")
                    .font(.caption.bold())
                    .foregroundStyle(Color.arcMuted)
                    .textCase(.uppercase)
                    .tracking(1)
                VStack(spacing: .arcS6) {
                    if let w = comic.writer    { creditRow(label: "Writer", value: w) }
                    if let p = comic.penciller { creditRow(label: "Art", value: p) }
                    if let a = comic.storyArc  { creditRow(label: "Arc", value: a) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.arcS16)
            .arcCard()
            .padding(.horizontal, .arcS24)
        }
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: .arcS8) {
            Text("Progress")
                .font(.caption.bold())
                .foregroundStyle(Color.arcMuted)
                .textCase(.uppercase)
                .tracking(1)
            if comic.pageCount > 0 {
                ArcProgressBar(value: comic.progress, height: 6)
                Text(progressLabel)
                    .font(.caption)
                    .foregroundStyle(Color.arcMuted)
            } else {
                Text("Page count unknown")
                    .font(.caption)
                    .foregroundStyle(Color.arcMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.arcS16)
        .arcCard()
        .padding(.horizontal, .arcS24)
    }

    private var progressLabel: String {
        if comic.isFinished { return "Finished" }
        if comic.currentPage == 0 { return "Not started" }
        return "Page \(comic.currentPage) of \(comic.pageCount)"
    }

    private func creditRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(Color.arcMuted)
                .frame(width: 50, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.white)
        }
    }

    private func toggleButton(label: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(active ? Color.arcGold.opacity(0.15) : Color.arcSurface)
                .foregroundStyle(active ? Color.arcGold : .white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? Color.arcGold : Color.arcBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func outlineButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: icon)
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.arcSurface)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.arcBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
