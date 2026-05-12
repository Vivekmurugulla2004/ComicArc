import SwiftUI

struct ComicDetailView: View {
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    let comicId: Int64
    @State private var comic: Comic?
    @State private var showReader = false
    @State private var showDeleteConfirm = false
    @State private var coverImage: UIImage?

    private let db = DatabaseManager.shared

    var body: some View {
        NavigationStack {
            Group {
                if let comic {
                    ScrollView {
                        VStack(spacing: 0) {
                            hero(comic)
                            details(comic)
                        }
                    }
                    .navigationTitle(comic.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbar(comic) }
                    .sheet(isPresented: $showReader) {
                        ReaderView(comic: comic)
                            .environmentObject(library)
                            .onDisappear { reload() }
                    }
                    .confirmationDialog(
                        "Remove from library? Your file will not be deleted.",
                        isPresented: $showDeleteConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Remove", role: .destructive) {
                            library.delete(comic)
                            dismiss()
                        }
                    }
                } else {
                    ProgressView()
                }
            }
        }
        .onAppear { reload() }
    }

    // MARK: - Hero

    private func hero(_ comic: Comic) -> some View {
        ZStack(alignment: .bottom) {
            if let img = coverImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 340)
                    .clipped()
                    .overlay(.ultraThinMaterial.opacity(0.4))
            } else {
                Color(.systemGray5)
                    .frame(height: 340)
            }

            VStack(spacing: 12) {
                if let img = coverImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 12)
                }

                Button {
                    showReader = true
                } label: {
                    Label(comic.progress > 0 ? "Continue Reading" : "Read",
                          systemImage: comic.progress > 0 ? "book.fill" : "book")
                        .font(.headline)
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Details

    private func details(_ comic: Comic) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            // Progress
            if comic.pageCount > 0 {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Progress")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text("Page \(comic.progress) of \(comic.pageCount)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ProgressView(value: comic.progressPercent)
                        .tint(.orange)
                    if comic.isFinished {
                        Text("Finished")
                            .font(.caption).foregroundStyle(.green)
                    }
                }
                .padding(.horizontal)
            }

            Divider().padding(.horizontal)

            // Rating
            VStack(alignment: .leading, spacing: 8) {
                Text("Rating").font(.subheadline).foregroundStyle(.secondary)
                    .padding(.horizontal)
                HStack(spacing: 12) {
                    ForEach(1...5, id: \.self) { i in
                        Image(systemName: i <= comic.rating ? "star.fill" : "star")
                            .font(.title2)
                            .foregroundStyle(i <= comic.rating ? .orange : Color(.systemGray3))
                            .onTapGesture {
                                db.setRating(comic.id, i == comic.rating ? 0 : i)
                                reload()
                                library.load()
                            }
                    }
                }
                .padding(.horizontal)
            }

            Divider().padding(.horizontal)

            // Metadata
            VStack(alignment: .leading, spacing: 12) {
                metaRow("Publisher", comic.publisher)
                if let char = comic.character { metaRow("Character", char) }
                if comic.series != "General"  { metaRow("Series", comic.series) }
                if let num = comic.issueNumber { metaRow("Issue", "#\(num)") }
                metaRow("Format", comic.fileExtension.uppercased())
                if comic.pageCount > 0 { metaRow("Pages", "\(comic.pageCount)") }
                if !comic.tags.isEmpty { metaRow("Tags", comic.tags.joined(separator: ", ")) }
            }
            .padding(.horizontal)

            Divider().padding(.horizontal)

            // Actions
            VStack(spacing: 12) {
                actionButton(
                    title: comic.isFavorite ? "Remove Favorite" : "Add to Favorites",
                    icon: comic.isFavorite ? "heart.slash" : "heart",
                    tint: .red
                ) {
                    db.setFavorite(comic.id, !comic.isFavorite)
                    reload(); library.load()
                }

                actionButton(
                    title: comic.inReadingList ? "Remove from Reading List" : "Want to Read",
                    icon: comic.inReadingList ? "bookmark.slash" : "bookmark",
                    tint: .blue
                ) {
                    db.setInReadingList(comic.id, !comic.inReadingList)
                    reload(); library.load()
                }

                if comic.isFinished || comic.isStarted {
                    actionButton(title: "Mark Unread", icon: "arrow.counterclockwise", tint: .gray) {
                        db.updateProgress(comicId: comic.id, page: 0)
                        reload(); library.load()
                    }
                }

                actionButton(title: "Remove from Library", icon: "trash", tint: .red) {
                    showDeleteConfirm = true
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .padding(.top, 20)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbar(_ comic: Comic) -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                db.setFavorite(comic.id, !comic.isFavorite)
                reload(); library.load()
            } label: {
                Image(systemName: comic.isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(comic.isFavorite ? .red : .primary)
            }
        }
    }

    // MARK: - Helpers

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value)
                .font(.subheadline)
            Spacer()
        }
    }

    private func actionButton(title: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }

    private func reload() {
        comic = db.comic(id: comicId)
        if let c = comic {
            Task {
                coverImage = await ThumbnailCache.shared.thumbnail(comicId: c.id)
            }
        }
    }
}
