import SwiftUI
import PhotosUI

struct ComicDetailView: View {
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var comic: Comic
    @State private var showReader = false
    @State private var showMissingFileAlert = false
    @State private var showDeleteConfirm = false
    @State private var showMetadataEditor = false
    @State private var showAddToRun = false
    @State private var showCustomCoverPicker = false
    @State private var showAddToCollection = false
    @State private var coverImage: UIImage?
    @State private var newTagText: String = ""

    init(comic: Comic) {
        _comic = State(initialValue: comic)
    }

    private func openComic(_ comic: Comic) {
        if FileManager.default.fileExists(atPath: comic.filePath) {
            showReader = true
        } else {
            showMissingFileAlert = true
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sizeClass == .regular {
                    iPadLayout(comic)
                } else {
                    iPhoneLayout(comic)
                }
            }
            .background(Color.arcBg)
            .navigationTitle(comic.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar(comic) }
            .sheet(isPresented: $showReader) {
                ReaderView(comic: comic).environmentObject(library)
            }
            .sheet(isPresented: $showMetadataEditor) {
                MetadataEditorView(comicId: comic.id) { library.reloadAfterExternalWrite() }
            }
            .sheet(isPresented: $showAddToRun) {
                AddToRunView(comicId: comic.id)
            }
            .sheet(isPresented: $showCustomCoverPicker) {
                CustomCoverPickerView(comic: comic) { newImage in
                    coverImage = newImage
                    Task { await ThumbnailCache.shared.setCustomCover(comicId: comic.id, image: newImage) }
                }
            }
            .sheet(isPresented: $showAddToCollection) {
                ComicCollectionPickerSheet(comic: comic)
                    .environmentObject(library)
            }
            .confirmationDialog(
                "Move this comic to Trash? You can restore it from the Trash tab within 30 days.",
                isPresented: $showDeleteConfirm, titleVisibility: .visible
            ) {
                Button("Move to Trash", role: .destructive) {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    library.delete(comic); dismiss()
                }
            }
            .alert("File Not Found", isPresented: $showMissingFileAlert) {
                Button("Remove from Library", role: .destructive) { library.delete(comic); dismiss() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This comic's file can't be found. It may have been moved or deleted.")
            }
            .onChange(of: library.comics) { _, newComics in
                if let updated = newComics.first(where: { $0.id == comic.id }) { comic = updated }
            }
        }
        .task(id: comic.id) {
            if coverImage == nil {
                coverImage = await ThumbnailCache.shared.thumbnail(comic: comic)
            }
        }
    }

    private func iPhoneLayout(_ comic: Comic) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                compactHero(comic)
                details(comic)
            }
        }
    }

    private func iPadLayout(_ comic: Comic) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView {
                VStack(spacing: .arcS20) {
                    coverThumbnail(height: nil)
                        .clipShape(RoundedRectangle(cornerRadius: .arcInnerRadius))
                        .shadow(radius: 16)

                    readButton(comic)
                }
                .padding(.arcS24)
            }
            .frame(maxWidth: 300)
            .background(Color.arcSurface.opacity(0.4))

            Divider()

            ScrollView {
                details(comic).padding(.top, 8)
            }
        }
    }

    private func compactHero(_ comic: Comic) -> some View {
        HStack(alignment: .top, spacing: .arcS16) {
            coverThumbnail(height: 150)
                .frame(width: 100)
                .clipShape(RoundedRectangle(cornerRadius: .arcInnerRadius))
                .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 4)
                .onTapGesture { showCustomCoverPicker = true }
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 11))
                        .padding(5)
                        .background(.ultraThinMaterial, in: Circle())
                        .padding(4)
                }

            VStack(alignment: .leading, spacing: .arcS8) {
                Text(comic.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(3)

                PublisherBadge(publisher: comic.publisher)

                if comic.series != "General" {
                    Text(comic.series)
                        .font(.caption)
                        .foregroundStyle(Color.arcMuted)
                        .lineLimit(1)
                }

                Spacer()

                readButton(comic)
            }

            Spacer(minLength: 0)
        }
        .padding(.arcS16)
        .background(Color.arcSurface)
    }

    @ViewBuilder
    private func coverThumbnail(height: CGFloat?) -> some View {
        Group {
            if let img = coverImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.arcCard
                    .overlay {
                        Image(systemName: "book.closed")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .aspectRatio(2/3, contentMode: .fit)
            }
        }
        .frame(height: height)
    }

    private func readButton(_ comic: Comic) -> some View {
        Button { openComic(comic) } label: {
            Label(comic.isStarted ? "Continue Reading" : "Read",
                  systemImage: comic.isStarted ? "book.fill" : "book")
                .font(.subheadline.bold())
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.arcGold)
        .accessibilityLabel(comic.isStarted ? "Continue reading \(comic.title)" : "Read \(comic.title)")
    }

    private func details(_ comic: Comic) -> some View {
        VStack(alignment: .leading, spacing: .arcS20) {
            if comic.pageCount > 0 { progressSection(comic); Divider().padding(.horizontal) }
            ratingSection(comic);    Divider().padding(.horizontal)
            tagsSection;             Divider().padding(.horizontal)
            metaSection(comic);      Divider().padding(.horizontal)
            actionsSection(comic)
        }
        .padding(.top, .arcS20)
        .padding(.bottom, 32)
    }

    private func progressSection(_ comic: Comic) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Progress").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("Page \(comic.progress + 1) of \(comic.pageCount)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ArcProgressBar(value: comic.progressPercent,
                           color: comic.isFinished ? .green : .arcGold)
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
            HStack(spacing: .arcS12) {
                ForEach(1...5, id: \.self) { i in
                    let newRating = i == comic.rating ? 0 : i
                    Image(systemName: i <= comic.rating ? "star.fill" : "star")
                        .font(.title2)
                        .foregroundStyle(i <= comic.rating ? Color.arcGold : Color.arcMuted)
                        .onTapGesture {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            library.apply(.setRating(id: comic.id, value: newRating))
                            self.comic.rating = newRating
                        }
                        .accessibilityLabel("\(i) star\(i == 1 ? "" : "s")\(i == comic.rating ? ", selected. Tap to clear." : "")")
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
                    ForEach(comic.tags, id: \.self) { tag in
                        HStack(spacing: 4) {
                            Text(tag)
                            Button {
                                let remaining = comic.tags.filter { $0 != tag }
                                comic.tags = remaining
                                library.apply(.setTags(id: comic.id, tags: remaining))
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                            }
                            .accessibilityLabel("Remove \(tag) tag")
                        }
                        .font(.caption)
                        .padding(.horizontal, .arcS10).padding(.vertical, .arcS4)
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
                                Image(systemName: "plus.circle.fill").font(.caption)
                            }
                        }
                    }
                    .padding(.horizontal, .arcS10).padding(.vertical, .arcS4)
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
        guard !name.isEmpty, !comic.tags.contains(name) else { newTagText = ""; return }
        newTagText = ""
        comic.tags.append(name)
        library.apply(.setTags(id: comic.id, tags: comic.tags))
    }

    private func metaSection(_ comic: Comic) -> some View {
        VStack(alignment: .leading, spacing: .arcS10) {
            metaRow("Publisher", comic.publisher)
            if let char = comic.character   { metaRow("Character", char) }
            if comic.series != "General"    { metaRow("Series", comic.series) }
            if let num = comic.issueNumber  { metaRow("Issue", "#\(num)") }
            if let writer = comic.writer, !writer.isEmpty       { metaRow("Writer", writer) }
            if let penciller = comic.penciller, !penciller.isEmpty { metaRow("Penciller", penciller) }
            if let arc = comic.storyArc, !arc.isEmpty           { metaRow("Story Arc", arc) }
            if let year = comic.year                            { metaRow("Year", String(year)) }
            if let lang = comic.languageISO, !lang.isEmpty      { metaRow("Language", lang.uppercased()) }
            metaRow("Format", comic.fileExtension.uppercased())
            if comic.pageCount > 0 { metaRow("Pages", "\(comic.pageCount)") }
            if let summary = comic.summary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Summary").font(.subheadline).foregroundStyle(.secondary)
                    Text(summary).font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let notes = comic.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes").font(.subheadline).foregroundStyle(.secondary)
                    Text(notes).font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal)
    }

    private func actionsSection(_ comic: Comic) -> some View {
        let id = comic.id
        return VStack(spacing: .arcS10) {
            actionButton(title: comic.isFavorite ? "Remove Favorite" : "Add to Favorites",
                         icon: comic.isFavorite ? "heart.slash" : "heart", tint: .red) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                let val = !comic.isFavorite
                library.apply(.setFavorite(id: id, value: val))
                self.comic.isFavorite = val
            }

            actionButton(title: comic.inReadingList ? "Remove from Reading List" : "Want to Read",
                         icon: comic.inReadingList ? "bookmark.slash" : "bookmark", tint: .blue) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                let val = !comic.inReadingList
                library.apply(.setInReadingList(id: id, value: val))
                self.comic.inReadingList = val
            }

            actionButton(title: "Add to Reading Run", icon: "list.number", tint: .purple) {
                showAddToRun = true
            }

            actionButton(title: "Add to Collection", icon: "folder.badge.plus", tint: .orange) {
                showAddToCollection = true
            }

            actionButton(title: "Set Custom Cover", icon: "photo", tint: .indigo) {
                showCustomCoverPicker = true
            }

            if comic.customCoverPath != nil {
                actionButton(title: "Reset to Original Cover", icon: "arrow.counterclockwise.circle", tint: .gray) {
                    ThumbnailCache.shared.clearCustomCover(comicId: comic.id)
                    self.comic.customCoverPath = nil
                    coverImage = nil
                    Task { coverImage = await ThumbnailCache.shared.thumbnail(comic: comic) }
                }
            }

            actionButton(title: "Edit Metadata", icon: "pencil", tint: .gray) {
                showMetadataEditor = true
            }

            if comic.pageCount > 0 && !comic.isFinished {
                actionButton(title: "Mark as Read", icon: "checkmark.circle", tint: .green) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    library.apply(.setProgress(id: id, page: comic.pageCount - 1))
                    self.comic.progress = comic.pageCount - 1
                }
            }

            if comic.isFinished || comic.isStarted {
                actionButton(title: "Mark Unread", icon: "arrow.counterclockwise", tint: .gray) {
                    library.apply(.setProgress(id: id, page: 0))
                    self.comic.progress = 0
                }
            }

            actionButton(title: "Delete Comic", icon: "trash", tint: .red) {
                showDeleteConfirm = true
            }
        }
        .padding(.horizontal)
    }

    @ToolbarContentBuilder
    private func toolbar(_ comic: Comic) -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                let val = !comic.isFavorite
                library.apply(.setFavorite(id: comic.id, value: val))
                self.comic.isFavorite = val
            } label: {
                Image(systemName: comic.isFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(comic.isFavorite ? .red : .primary)
            }
            .accessibilityLabel(comic.isFavorite ? "Remove from favorites" : "Add to favorites")
        }
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
            Text(value).font(.subheadline)
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
}

struct CustomCoverPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let comic: Comic
    let onSelect: (UIImage) -> Void

    @State private var selectedItem: PhotosPickerItem?
    @State private var showPagePicker = false
    @State private var currentPage: Int = 0

    var body: some View {
        NavigationStack {
            List {
                Section("Choose Source") {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        Label("From Photos Library", systemImage: "photo.on.rectangle")
                    }
                    .onChange(of: selectedItem) { _, item in
                        guard let item else { return }
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let img = UIImage(data: data) {
                                onSelect(img)
                                dismiss()
                            }
                        }
                    }

                    if comic.pageCount > 0 {
                        Button {
                            showPagePicker = true
                        } label: {
                            Label("From Comic Pages", systemImage: "book.pages")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.arcBg)
            .navigationTitle("Set Cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
            .sheet(isPresented: $showPagePicker) {
                PageCoverPickerView(comic: comic) { img in
                    onSelect(img)
                    dismiss()
                }
            }
        }
    }
}

struct PageCoverPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let comic: Comic
    let onSelect: (UIImage) -> Void

    @State private var currentPage = 0
    @State private var pageImage: UIImage?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    if let img = pageImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .shadow(radius: 8)
                            .padding()
                    } else if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.arcBg)

                VStack(spacing: 12) {
                    if comic.pageCount > 1 {
                        HStack {
                            Button { movePage(-1) } label: {
                                Image(systemName: "chevron.left.circle.fill")
                                    .font(.title2)
                            }
                            .disabled(currentPage == 0)

                            Spacer()
                            Text("Page \(currentPage + 1) of \(comic.pageCount)")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Spacer()

                            Button { movePage(1) } label: {
                                Image(systemName: "chevron.right.circle.fill")
                                    .font(.title2)
                            }
                            .disabled(currentPage >= comic.pageCount - 1)
                        }
                        .foregroundStyle(Color.arcGold)
                        .padding(.horizontal)
                    }

                    Button {
                        if let img = pageImage { onSelect(img); dismiss() }
                    } label: {
                        Text("Use This Page as Cover")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.arcGold)
                    .disabled(pageImage == nil)
                    .padding(.horizontal)
                }
                .padding(.vertical, 16)
                .background(Color.arcSurface)
            }
            .background(Color.arcBg)
            .navigationTitle("Pick Cover Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
            .task(id: currentPage) { await loadPage() }
        }
    }

    private func movePage(_ delta: Int) {
        let next = currentPage + delta
        guard next >= 0, next < comic.pageCount else { return }
        currentPage = next
    }

    private func loadPage() async {
        isLoading = true
        pageImage = nil
        pageImage = await loadPageImage(comic: comic, index: currentPage)
        isLoading = false
    }
}
