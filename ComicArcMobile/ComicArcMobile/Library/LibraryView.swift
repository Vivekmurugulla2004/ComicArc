import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showImporter = false
    @State private var showFolderImporter = false
    @State private var browseMode: BrowseMode = .characters
    @State private var selectedCharacter: SeriesGroup?
    @State private var selectedSeries: SeriesGroup?
    @State private var detailComic: Comic?
    @State private var continueComic: Comic?

    // Selection
    @State private var isSelecting = false
    @State private var selectedIds: Set<Int64> = []
    @State private var showBulkDeleteConfirm = false

    // Filter state — @State here so changes ONLY invalidate LibraryView, not other tabs
    @State private var selectedPublisher: String = "All"
    @State private var sortOrder: DatabaseManager.SortOrder = .publisher
    @State private var searchText: String = ""
    @State private var selectedTag: String?

    // Smart filters
    @State private var selectedSmartFilter: SmartFilter? = nil

    // Cached filtered comics — updated via onChange instead of recomputed on every body pass
    @State private var filteredComics: [Comic] = []

    // Continue Run
    @State private var activeRun: Run?
    @State private var selectedRun: Run?

    @State private var missingFileComic: Comic?

    enum BrowseMode { case characters, flat }

    enum SmartFilter: String, CaseIterable {
        case recentlyAdded = "New"
        case inProgress    = "In Progress"
        case unread        = "Unread"
        case finished      = "Finished"
    }

    private var phoneColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 130), spacing: 12)]
    }

    private var ipadColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 180), spacing: 16)]
    }

    private var columns: [GridItem] {
        sizeClass == .regular ? ipadColumns : phoneColumns
    }

    // True when user is actively searching — bypass the hierarchy
    private var isSearching: Bool { !searchText.isEmpty }

    private func updateFilteredComics(_ comics: [Comic]) {
        guard let filter = selectedSmartFilter else { filteredComics = comics; return }
        switch filter {
        case .recentlyAdded:
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            filteredComics = comics.filter { $0.dateAdded >= cutoff }
        case .inProgress:
            filteredComics = comics.filter { $0.isStarted && !$0.isFinished }
        case .unread:
            filteredComics = comics.filter { !$0.isStarted }
        case .finished:
            filteredComics = comics.filter { $0.isFinished }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                // iPad character browse: two-panel layout
                if sizeClass == .regular && browseMode == .characters && !isSearching {
                    ipadCharacterBrowse
                } else {
                    phoneScrollContent
                }
            }
            .navigationTitle(isSelecting ? "\(selectedIds.count) Selected" : navigationTitle)
            .background(Color.arcBg)
            .navigationBarTitleDisplayMode(sizeClass == .regular ? .inline : .large)
            .searchable(text: $searchText, prompt: "Search comics")
            .onChange(of: searchText) { _, _ in
                if isSelecting { exitSelection() }
                selectedSmartFilter = nil
                updateFilteredComics(library.comics)
            }
            .task(id: searchText) {
                if !searchText.isEmpty {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard !Task.isCancelled else { return }
                }
                reload()
            }
            .onChange(of: browseMode) { _, _ in
                selectedSmartFilter = nil
                selectedCharacter = nil
                selectedSeries = nil
                reload()
            }
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) {
                if isSelecting { bulkActionsToolbar }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.init(filenameExtension: "cbz")!, .init(filenameExtension: "cbr")!, .pdf, .jpeg, .png],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result { library.importFiles(urls) }
            }
            .fileImporter(
                isPresented: $showFolderImporter,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    library.importFolder(url)
                }
            }
            .onAppear { reload(); loadActiveRun(); updateFilteredComics(library.comics) }
            .onChange(of: library.comics) { _, newComics in updateFilteredComics(newComics) }
            .onChange(of: selectedSmartFilter) { _, _ in updateFilteredComics(library.comics) }
            .sheet(item: $detailComic) { comic in
                ComicDetailView(comic: comic)
                    .environmentObject(library)
            }
            .sheet(item: $continueComic) { comic in
                ReaderView(comic: comic)
                    .environmentObject(library)
            }
            .sheet(item: $selectedRun) { run in
                RunDetailView(run: run)
                    .environmentObject(library)
                    .onDisappear { loadActiveRun() }
            }
            .confirmationDialog(
                "Delete \(selectedIds.count) comic\(selectedIds.count == 1 ? "" : "s")? This cannot be undone.",
                isPresented: $showBulkDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { bulkDelete() }
            }
            .alert("Import Error", isPresented: Binding(
                get: { library.importError != nil },
                set: { if !$0 { library.importError = nil } }
            )) {
                Button("OK", role: .cancel) { library.importError = nil }
            } message: {
                Text(library.importError ?? "")
            }
            .alert("File Not Found", isPresented: Binding(
                get: { missingFileComic != nil },
                set: { if !$0 { missingFileComic = nil } }
            )) {
                Button("Remove from Library", role: .destructive) {
                    if let c = missingFileComic { library.delete(c) }
                    missingFileComic = nil
                }
                Button("Cancel", role: .cancel) { missingFileComic = nil }
            } message: {
                Text("The file for \"\(missingFileComic?.title ?? "this comic")\" can't be found on your device.")
            }
        }
    }

    // MARK: - iPad Two-Panel Layout

    private var ipadCharacterBrowse: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left panel: character list + contextual sections
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if library.importProgress.isActive {
                            importBanner.padding(.horizontal, 12).padding(.top, 8)
                        }
                        if !library.publishers.isEmpty {
                            publisherFilterRow.padding(.horizontal, 12)
                        }
                        if !library.inProgress.isEmpty {
                            continueReadingSection.padding(.horizontal, 12)
                        }
                        continueRunSection.padding(.horizontal, 12)

                        if library.characterGroups.isEmpty {
                            EmptyStateView(
                                icon: "books.vertical",
                                title: "No Comics Yet",
                                message: "Tap + to import files.",
                                actionTitle: "Import Comics",
                                action: { showImporter = true }
                            )
                            .padding(.top, 24)
                        } else {
                            ForEach(library.characterGroups) { group in
                                ipadCharacterRow(group)
                            }
                        }
                        Spacer(minLength: 24)
                    }
                }
            }
            .frame(width: 280)
            .background(Color.arcSurface.ignoresSafeArea(edges: .bottom))

            Divider().ignoresSafeArea()

            // Right panel: series or issues
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let series = selectedSeries {
                        ipadIssuePanel(series: series)
                    } else if selectedCharacter != nil {
                        ipadSeriesPanel
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "arrow.left")
                                .font(.title2)
                                .foregroundStyle(Color.arcMuted)
                            Text("Select a character")
                                .font(.subheadline)
                                .foregroundStyle(Color.arcMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 100)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.arcBg)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func ipadCharacterRow(_ group: SeriesGroup) -> some View {
        let isSelected = selectedCharacter?.id == group.id
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if isSelected {
                    selectedCharacter = nil
                    selectedSeries = nil
                } else {
                    selectCharacter(group)
                }
            }
        } label: {
            HStack(spacing: 10) {
                CoverImage(comicId: group.coverComicId)
                    .frame(width: 38, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.groupName)
                        .font(.subheadline)
                        .fontWeight(isSelected ? .bold : .regular)
                        .foregroundStyle(isSelected ? Color.arcGold : .white)
                        .lineLimit(1)
                    Text("\(group.issueCount) issue\(group.issueCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if group.isFinished {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else if group.isReading {
                    Image(systemName: "book.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.arcGold)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.arcGold : Color.arcMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.arcGold.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var ipadSeriesPanel: some View {
        Group {
            if library.seriesGroups.isEmpty {
                EmptyStateView(
                    icon: "books.vertical",
                    title: "No Series Found",
                    message: "No series match the current filter."
                )
                .padding(.top, 60)
            } else {
                LazyVGrid(columns: ipadColumns, spacing: 16) {
                    ForEach(library.seriesGroups) { group in
                        SeriesCard(group: group, characterName: selectedCharacter?.groupName)
                            .onTapGesture {
                                withAnimation { selectSeries(group) }
                            }
                    }
                }
                .padding()
            }
        }
    }

    private func ipadIssuePanel(series: SeriesGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Back to series (only when character has sub-series)
            if selectedCharacter?.character != nil {
                Button {
                    withAnimation { selectedSeries = nil }
                } label: {
                    Label("Back to \(selectedCharacter?.groupName ?? "Series")",
                          systemImage: "chevron.left")
                        .font(.subheadline)
                        .foregroundStyle(Color.arcGold)
                }
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }

            if filteredComics.isEmpty {
                EmptyStateView(
                    icon: "books.vertical",
                    title: "No Issues",
                    message: "No issues match the current filter."
                )
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: ipadColumns, spacing: 16) {
                    ForEach(filteredComics) { comic in
                        selectableComicCard(comic)
                    }
                }
                .padding()
            }
        }
    }

    // MARK: - Phone Scroll Content

    private var phoneScrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if library.importProgress.isActive { importBanner }

                if !library.publishers.isEmpty && !isSearching {
                    publisherFilterRow
                }

                if (browseMode == .flat || isSearching) && !library.allTags.isEmpty {
                    tagFilterRow
                }

                if browseMode == .flat || isSearching {
                    smartFilterRow
                }

                if isSearching {
                    flatGrid
                } else if browseMode == .characters {
                    if selectedCharacter != nil {
                        breadcrumbBar
                    }
                    if let series = selectedSeries {
                        issueGrid(series: series)
                    } else if let char = selectedCharacter {
                        seriesGrid(character: char)
                    } else {
                        if !library.inProgress.isEmpty { continueReadingSection }
                        continueRunSection
                        characterGrid
                    }
                } else {
                    if !library.inProgress.isEmpty && selectedTag == nil {
                        continueReadingSection
                    }
                    continueRunSection
                    flatGrid
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Import Banner

    private var importBanner: some View {
        HStack(spacing: 10) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                if library.importProgress.isScanning {
                    Text("Scanning folder…")
                        .font(.subheadline)
                } else {
                    Text("Importing \(library.importProgress.done + 1) of \(library.importProgress.total)…")
                        .font(.subheadline)
                    if !library.importProgress.currentFile.isEmpty {
                        Text(library.importProgress.currentFile)
                            .font(.caption2)
                            .foregroundStyle(Color.arcMuted)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            Spacer()
            if library.importProgress.failures > 0 {
                Text("\(library.importProgress.failures) failed")
                    .font(.caption2.bold())
                    .foregroundStyle(Color.arcRed)
            }
            Button("Cancel") { library.cancelImport() }
                .font(.caption.bold())
                .foregroundStyle(Color.arcGold)
        }
        .padding(12)
        .background(Color.arcGold.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.top, 8)
    }

    // MARK: - Publisher Filter Row

    private var publisherFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", isActive: selectedPublisher == "All") {
                    selectPublisher("All")
                }
                ForEach(library.publishers, id: \.self) { pub in
                    FilterChip(label: pub, isActive: selectedPublisher == pub) {
                        selectPublisher(selectedPublisher == pub ? "All" : pub)
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Tag Filter Row

    private var tagFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(label: "All", isActive: selectedTag == nil) {
                    selectedTag = nil
                    reload()
                }
                ForEach(library.allTags) { tag in
                    FilterChip(label: tag.name, isActive: selectedTag == tag.name) {
                        selectedTag = (selectedTag == tag.name) ? nil : tag.name
                        reload()
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if isSelecting {
                Button {
                    let allIds = Set(filteredComics.map(\.id))
                    withAnimation {
                        selectedIds = (selectedIds == allIds) ? [] : allIds
                    }
                } label: {
                    Text(selectedIds.count == filteredComics.count && !filteredComics.isEmpty
                         ? "None" : "All")
                        .font(.subheadline)
                }
                .accessibilityLabel("Select all or deselect all")
            } else {
                if !isSearching {
                    Picker("Browse Mode", selection: $browseMode) {
                        Image(systemName: "square.grid.2x2").tag(BrowseMode.characters)
                            .accessibilityLabel("Character View")
                        Image(systemName: "list.bullet").tag(BrowseMode.flat)
                            .accessibilityLabel("All Comics")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 80)
                    .accessibilityLabel("Browse Mode")

                    Menu {
                        ForEach(DatabaseManager.SortOrder.allCases, id: \.self) { order in
                            Button {
                                sortOrder = order
                                reload()
                            } label: {
                                Label(order.rawValue,
                                      systemImage: sortOrder == order ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .accessibilityLabel("Sort Comics")
                    }
                }

                // Import menu: files or folder
                Menu {
                    Button { showImporter = true } label: {
                        Label("Import Files", systemImage: "doc.badge.plus")
                    }
                    Button { showFolderImporter = true } label: {
                        Label("Import Folder", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Import Comics")
            }
        }
        ToolbarItem(placement: .topBarLeading) {
            if isSelecting {
                Button("Cancel") { exitSelection() }
                    .accessibilityLabel("Cancel selection")
            } else if !isSearching && (selectedSeries != nil || selectedCharacter != nil) {
                Button {
                    withAnimation {
                        if selectedSeries != nil {
                            selectedSeries = nil
                            if selectedCharacter?.character == nil {
                                selectedCharacter = nil
                            }
                        } else {
                            selectedCharacter = nil
                        }
                    }
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }
        }
    }

    // MARK: - Continue Reading

    private var continueReadingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Continue Reading").font(.headline).padding(.top, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(library.inProgress) { comic in
                        ContinueCard(comic: comic)
                            .onTapGesture {
                                if FileManager.default.fileExists(atPath: comic.filePath) {
                                    continueComic = comic
                                } else {
                                    missingFileComic = comic
                                }
                            }
                    }
                }
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Grids

    private var characterGrid: some View {
        Group {
            if library.characterGroups.isEmpty {
                EmptyStateView(
                    icon: "books.vertical",
                    title: "No Comics Yet",
                    message: "Tap + to import CBZ or PDF files, or import an entire folder at once.",
                    actionTitle: "Import Comics",
                    action: { showImporter = true }
                )
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(library.characterGroups) { group in
                        SeriesCard(group: group)
                            .onTapGesture {
                                withAnimation { selectCharacter(group) }
                            }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func seriesGrid(character: SeriesGroup) -> some View {
        Group {
            if library.seriesGroups.isEmpty {
                EmptyStateView(
                    icon: "books.vertical",
                    title: "No Series Found",
                    message: "No series for \(character.groupName) match the current publisher filter."
                )
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(library.seriesGroups) { group in
                        SeriesCard(group: group, characterName: character.groupName)
                            .onTapGesture {
                                withAnimation { selectSeries(group) }
                            }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private func issueGrid(series: SeriesGroup) -> some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(filteredComics) { comic in
                selectableComicCard(comic)
            }
        }
        .padding(.top, 8)
    }

    private var flatGrid: some View {
        Group {
            if filteredComics.isEmpty {
                if searchText.isEmpty && selectedSmartFilter == nil {
                    EmptyStateView(
                        icon: "books.vertical",
                        title: "No Comics Yet",
                        message: "Tap + to import CBZ or PDF files, or import an entire folder at once.",
                        actionTitle: "Import Comics",
                        action: { showImporter = true }
                    )
                    .padding(.top, 60)
                } else if let filter = selectedSmartFilter {
                    EmptyStateView(
                        icon: "line.3.horizontal.decrease",
                        title: "No \(filter.rawValue) Comics",
                        message: "No comics match this filter right now."
                    )
                    .padding(.top, 60)
                } else {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No Results",
                        message: "Nothing matched \"\(searchText)\". Try a different title or series."
                    )
                    .padding(.top, 60)
                }
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(filteredComics) { comic in
                        selectableComicCard(comic)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var navigationTitle: String {
        if isSearching                        { return "Search Results" }
        if let s = selectedSeries             { return s.groupName }
        if let c = selectedCharacter          { return c.groupName }
        if let t = selectedTag                 { return t }
        return "Library"
    }

    // MARK: - Selectable Card

    @ViewBuilder
    private func selectableComicCard(_ comic: Comic) -> some View {
        let isSelected = selectedIds.contains(comic.id)
        ComicCard(comic: comic)
            .overlay(alignment: .topLeading) {
                if isSelecting {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? Color.arcGold : .white)
                        .background(Circle()
                            .fill(isSelected ? Color.arcBg : Color.black.opacity(0.5))
                            .padding(-3))
                        .padding(8)
                        .animation(.easeInOut(duration: 0.15), value: isSelected)
                }
            }
            .overlay {
                if isSelecting && isSelected {
                    RoundedRectangle(cornerRadius: .arcCardRadius)
                        .stroke(Color.arcGold, lineWidth: 2)
                        .animation(.easeInOut(duration: 0.15), value: isSelected)
                }
            }
            .onTapGesture {
                if isSelecting {
                    withAnimation(.easeInOut(duration: 0.15)) { toggleSelection(comic.id) }
                } else {
                    detailComic = comic
                }
            }
            .contextMenu {
                if !isSelecting {
                    Button {
                        withAnimation { isSelecting = true; selectedIds.insert(comic.id) }
                    } label: {
                        Label("Select", systemImage: "checkmark.circle")
                    }
                    Divider()
                    Button {
                        guard comic.pageCount > 0 else { return }
                        library.apply(.setProgress(id: comic.id, page: comic.pageCount - 1))
                    } label: {
                        Label("Mark as Read", systemImage: "checkmark.circle.fill")
                    }
                    Button {
                        library.apply(.setFavorite(id: comic.id, value: !comic.isFavorite))
                    } label: {
                        Label(comic.isFavorite ? "Remove Favorite" : "Add to Favorites",
                              systemImage: comic.isFavorite ? "heart.slash" : "heart")
                    }
                    Button {
                        library.apply(.setInReadingList(id: comic.id, value: !comic.inReadingList))
                    } label: {
                        Label(comic.inReadingList ? "Remove from Reading List" : "Want to Read",
                              systemImage: comic.inReadingList ? "bookmark.slash" : "bookmark")
                    }
                    Button { detailComic = comic } label: {
                        Label("View Details", systemImage: "info.circle")
                    }
                    Divider()
                    Button(role: .destructive) { library.delete(comic) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
    }

    // MARK: - Breadcrumb

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                breadcrumbSegment("Library") {
                    withAnimation { selectedCharacter = nil; selectedSeries = nil }
                }
                if let char = selectedCharacter {
                    Image(systemName: "chevron.right")
                        .font(.caption2).foregroundStyle(.secondary)
                    if selectedSeries != nil && char.character != nil {
                        breadcrumbSegment(char.groupName) {
                            withAnimation {
                                selectedSeries = nil
                                library.loadSeries(for: char.groupName,
                                                   publisher: selectedPublisher == "All" ? nil : selectedPublisher)
                            }
                        }
                        if let series = selectedSeries {
                            Image(systemName: "chevron.right")
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(series.groupName)
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                        }
                    } else {
                        Text(char.groupName)
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func breadcrumbSegment(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.caption2).foregroundStyle(Color.arcGold)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Smart Filter Row

    private var smartFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SmartFilter.allCases, id: \.self) { filter in
                    let active = selectedSmartFilter == filter
                    FilterChip(label: filter.rawValue, isActive: active, style: .outlined) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedSmartFilter = active ? nil : filter
                        }
                    }
                    .accessibilityLabel("\(filter.rawValue) filter\(active ? ", active" : "")")
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: - Continue Run Section

    private var continueRunSection: some View {
        Group {
            if let run = activeRun {
                Button { selectedRun = run } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "list.number")
                            .foregroundStyle(Color.arcGold)
                            .frame(width: 32, height: 32)
                            .background(Color.arcGold.opacity(0.15))
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(run.title)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                                .lineLimit(1)
                            Text("\(run.completedCount) of \(run.itemCount) issues")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.arcBorder)
                            Capsule()
                                .fill(Color.arcGold)
                                .frame(width: 56 * CGFloat(run.progressPercent))
                        }
                        .frame(width: 56, height: 4)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(Color.arcCard)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.arcBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 12)
                .accessibilityLabel("Continue run: \(run.title), \(run.completedCount) of \(run.itemCount) issues")
            }
        }
    }

    // MARK: - Bulk Actions Toolbar

    private var bulkActionsToolbar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 20) {
                Text(selectedIds.isEmpty ? "Tap comics to select" : "\(selectedIds.count) selected")
                    .font(.caption)
                    .foregroundStyle(selectedIds.isEmpty ? Color.arcMuted : .white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if !selectedIds.isEmpty {
                    Button { bulkMarkRead() } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "checkmark.circle").font(.title3)
                            Text("Read").font(.system(size: 9))
                        }
                    }
                    .accessibilityLabel("Mark selected as read")

                    Button { bulkToggleFavorite() } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "heart").font(.title3)
                            Text("Favorite").font(.system(size: 9))
                        }
                    }
                    .accessibilityLabel("Toggle favorite for selected")

                    Button { bulkToggleReadingList() } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "bookmark").font(.title3)
                            Text("Want").font(.system(size: 9))
                        }
                    }
                    .accessibilityLabel("Toggle reading list for selected")

                    Button { showBulkDeleteConfirm = true } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "trash").font(.title3).foregroundStyle(Color.arcRed)
                            Text("Delete").font(.system(size: 9)).foregroundStyle(Color.arcRed)
                        }
                    }
                    .accessibilityLabel("Delete selected comics")
                }
            }
            .foregroundStyle(Color.arcGold)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
        }
    }

    // MARK: - Navigation Helpers

    private func selectCharacter(_ group: SeriesGroup) {
        selectedSmartFilter = nil
        selectedCharacter = group
        selectedSeries = nil
        let pub = selectedPublisher == "All" ? nil : selectedPublisher
        if group.character != nil {
            library.loadSeries(for: group.groupName, publisher: pub)
        } else {
            selectedSeries = group
            library.loadIssues(character: nil, series: group.groupName, publisher: pub, sortOrder: sortOrder)
        }
    }

    private func selectSeries(_ group: SeriesGroup) {
        selectedSmartFilter = nil
        selectedSeries = group
        let pub = selectedPublisher == "All" ? nil : selectedPublisher
        library.loadIssues(
            character: selectedCharacter?.character,
            series: group.groupName,
            publisher: pub,
            sortOrder: sortOrder
        )
    }

    private func selectPublisher(_ publisher: String) {
        selectedPublisher = publisher
        selectedCharacter = nil
        selectedSeries = nil
        selectedSmartFilter = nil
        reload()
    }

    // MARK: - Bulk Action Helpers

    private func toggleSelection(_ id: Int64) {
        if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) }
    }

    private func exitSelection() {
        withAnimation(.easeInOut(duration: 0.2)) { isSelecting = false; selectedIds.removeAll() }
    }

    // Passes current @State filter values to the ViewModel load.
    // This is the single call site for triggering a DB query — all filter interactions funnel here.
    private func reload() {
        let pub = selectedPublisher == "All" ? nil : selectedPublisher
        library.load(
            publisher: pub,
            tag: selectedTag,
            search: searchText.isEmpty ? nil : searchText,
            sortOrder: sortOrder
        )
    }

    private func loadActiveRun() {
        Task {
            let run = await Task.detached(priority: .utility) {
                DatabaseManager.shared.firstActiveRun()
            }.value
            activeRun = run
        }
    }

    private func bulkMarkRead() {
        let mutations: [LibraryMutation] = library.comics
            .filter { selectedIds.contains($0.id) && $0.pageCount > 0 }
            .map { .setProgress(id: $0.id, page: $0.pageCount - 1) }
        exitSelection()
        library.applyBatch(mutations)
    }

    private func bulkToggleFavorite() {
        let affected  = library.comics.filter { selectedIds.contains($0.id) }
        let newVal    = !affected.allSatisfy(\.isFavorite)
        let mutations = affected.map { LibraryMutation.setFavorite(id: $0.id, value: newVal) }
        exitSelection()
        library.applyBatch(mutations)
    }

    private func bulkToggleReadingList() {
        let affected  = library.comics.filter { selectedIds.contains($0.id) }
        let newVal    = !affected.allSatisfy(\.inReadingList)
        let mutations = affected.map { LibraryMutation.setInReadingList(id: $0.id, value: newVal) }
        exitSelection()
        library.applyBatch(mutations)
    }

    private func bulkDelete() {
        library.deleteBatch(library.comics.filter { selectedIds.contains($0.id) })
        loadActiveRun()
        exitSelection()
    }
}

// MARK: - Continue Card

struct ContinueCard: View {
    let comic: Comic

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CoverImage(comic: comic)
                .frame(width: 90, height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.arcGold)
                        .frame(height: 3)
                        .scaleEffect(x: min(1, comic.progressPercent), y: 1, anchor: .leading)
                }
            Text(comic.title)
                .font(.caption2).lineLimit(2)
                .frame(width: 90, alignment: .leading)
            if comic.pageCount > 0 {
                Text("p.\(comic.progress + 1)/\(comic.pageCount)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Series Card

struct SeriesCard: View {
    let group: SeriesGroup
    var characterName: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cover — full-bleed, top corners clipped by parent arcCard.
            // Matches macOS .series-cover-wrap layout.
            ZStack(alignment: .topTrailing) {
                CoverImage(comicId: group.coverComicId)
                    .aspectRatio(2/3, contentMode: .fill)
                    .clipped()
                if group.isFinished {
                    badge("Done", color: .green)
                } else if group.isReading {
                    badge("Reading", color: .arcBlue)
                }
            }

            // Info section — matches macOS .series-info padding
            VStack(alignment: .leading, spacing: 4) {
                if let charName = characterName {
                    Text(charName.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.arcGold)
                        .lineLimit(1)
                }
                Text(group.groupName)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text("\(group.issueCount) issue\(group.issueCount == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .arcCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11yLabel)
    }

    private var a11yLabel: String {
        var parts = [group.groupName]
        if let c = characterName { parts.append(c) }
        parts.append("\(group.issueCount) issue\(group.issueCount == 1 ? "" : "s")")
        if group.isFinished { parts.append("Finished") }
        else if group.isReading { parts.append("In progress") }
        return parts.joined(separator: ", ")
    }

    private func badge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2).fontWeight(.bold)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color).foregroundStyle(.white)
            .clipShape(Capsule()).padding(4)
    }
}
