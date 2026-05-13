import SwiftUI

struct ComicDetailView: View {
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    @Environment(\.horizontalSizeClass) private var sizeClass
    let comicId: Int64
    @State private var comic: Comic?
    @State private var tags: [Tag] = []
    @State private var showReader = false
    @State private var showDeleteConfirm = false
    @State private var showMetadataEditor = false
    @State private var showAddToRun = false
    @State private var coverImage: UIImage?
    @State private var newTagText: String = ""

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
                    .background(Color.arcBg)
                    .navigationTitle(comic.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { toolbar(comic) }
                    .sheet(isPresented: $showReader, onDismiss: reload) {
                        ReaderView(comic: comic)
                            .environmentObject(library)
                    }
                    .sheet(isPresented: $showMetadataEditor, onDismiss: reload) {
                        MetadataEditorView(comicId: comicId) {
                            reload()
                            library.load()
                        }
                    }
                    .sheet(isPresented: $showAddToRun) {
                        AddToRunView(comicId: comicId)
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
            let heroHeight: CGFloat = sizeClass == .regular ? 480 : 320
            let coverHeight: CGFloat = sizeClass == .regular ? 300 : 190

            if let img = coverImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: heroHeight)
                    .clipped()
                    .overlay(.ultraThinMaterial.opacity(0.45))
            } else {
                Color.arcSurface.frame(height: heroHeight)
            }

            VStack(spacing: 12) {
                if let img = coverImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(height: coverHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 12)
                }

                Button {
                    showReader = true
                } label: {
                    Label(comic.isStarted ? "Continue Reading" : "Read",
                          systemImage: comic.isStarted ? "book.fill" : "book")
                        .font(.headline)
                        .frame(maxWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .tint(.arcGold)
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Details

    private func details(_ comic: Comic) -> some View {
        VStack(alignment: .leading, spacing: 20) {

            // Progress
            if comic.pageCount > 0 {
                progressSection(comic)
                Divider().padding(.horizontal)
            }

            // Rating
            ratingSection(comic)
            Divider().padding(.horizontal)

            // Tags (always shown so user can add)
            tagsSection
            Divider().padding(.horizontal)

            // Metadata
            metaSection(comic)
            Divider().padding(.horizontal)

            // Actions
            actionsSection(comic)
        }
        .padding(.top, 20)
        .padding(.bottom, 32)
    }

    private func progressSection(_ comic: Comic) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Progress").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("Page \(comic.progress) of \(comic.pageCount)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: comic.progressPercent).tint(.arcGold)
            if comic.isFinished {
                Label("Finished", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            }
        }
        .padding(.horizontal)
    }

    private func ratingSection(_ comic: Comic) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rating").font(.subheadline).foregroundStyle(.secondary)
                .padding(.horizontal)
            HStack(spacing: 12) {
                ForEach(1...5, id: \.self) { i in
                    Image(systemName: i <= comic.rating ? "star.fill" : "star")
                        .font(.title2)
                        .foregroundStyle(i <= comic.rating ? Color.arcGold : Color.arcMuted)
                        .onTapGesture {
                            db.setRating(comic.id, i == comic.rating ? 0 : i)
                            reload(); library.load()
                        }
                }
            }
            .padding(.horizontal)
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags").font(.subheadline).foregroundStyle(.secondary)
                .padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tags) { tag in
                        HStack(spacing: 4) {
                            Text(tag.name)
                            Button {
                                let remaining = tags.filter { $0.id != tag.id }.map(\.name)
                                db.setTags(for: comicId, names: remaining)
                                reload()
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                            }
                        }
                        .font(.caption)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Color.arcGold.opacity(0.15))
                        .foregroundStyle(Color.arcGold)
                        .clipShape(Capsule())
                    }

                    HStack(spacing: 4) {
                        TextField("Add tag", text: $newTagText)
                            .font(.caption)
                            .frame(minWidth: 60, maxWidth: 100)
                            .onSubmit { addTag() }
                        if !newTagText.isEmpty {
                            Button { addTag() } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.arcSurface)
                    .overlay(Capsule().stroke(Color.arcBorder, lineWidth: 1))
                    .clipShape(Capsule())
                    .foregroundStyle(Color.arcGold)
                }
                .padding(.horizontal)
            }
        }
    }

    private func addTag() {
        let name = newTagText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let existing = tags.map(\.name)
        guard !existing.contains(name) else { newTagText = ""; return }
        db.setTags(for: comicId, names: existing + [name])
        newTagText = ""
        reload()
    }

    private func metaSection(_ comic: Comic) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            metaRow("Publisher", comic.publisher)
            if let char = comic.character { metaRow("Character", char) }
            if comic.series != "General"  { metaRow("Series", comic.series) }
            if let num = comic.issueNumber { metaRow("Issue", "#\(num)") }
            metaRow("Format", comic.fileExtension.uppercased())
            if comic.pageCount > 0 { metaRow("Pages", "\(comic.pageCount)") }
        }
        .padding(.horizontal)
    }

    private func actionsSection(_ comic: Comic) -> some View {
        VStack(spacing: 10) {
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

            actionButton(title: "Add to Reading Run",
                         icon: "list.number", tint: .purple) {
                showAddToRun = true
            }

            actionButton(title: "Edit Metadata",
                         icon: "pencil", tint: .gray) {
                showMetadataEditor = true
            }

            if comic.pageCount > 0 && !comic.isFinished {
                actionButton(title: "Mark as Read",
                             icon: "checkmark.circle", tint: .green) {
                    db.updateProgress(comicId: comic.id, page: comic.pageCount - 1)
                    reload(); library.load()
                }
            }

            if comic.isFinished || comic.isStarted {
                actionButton(title: "Mark Unread",
                             icon: "arrow.counterclockwise", tint: .gray) {
                    db.updateProgress(comicId: comic.id, page: 0)
                    reload(); library.load()
                }
            }

            actionButton(title: "Remove from Library",
                         icon: "trash", tint: .red) {
                showDeleteConfirm = true
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private func toolbar(_ comic: Comic) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
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
            Text(value).font(.subheadline)
            Spacer()
        }
    }

    private func actionButton(title: String, icon: String, tint: Color,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }

    private func reload() {
        comic = db.comic(id: comicId)
        tags  = db.tags(for: comicId)
        if let c = comic {
            Task { coverImage = await ThumbnailCache.shared.thumbnail(comicId: c.id) }
        }
    }
}
