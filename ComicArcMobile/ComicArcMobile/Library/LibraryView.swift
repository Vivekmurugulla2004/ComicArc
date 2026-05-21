import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showImporter = false
    @State private var showFolderImporter = false
    @State private var selectedCharacter: SeriesGroup?
    @State private var selectedSeries: SeriesGroup?
    @State private var detailComic: Comic?
    @State private var continueComic: Comic?

    @State private var isSelecting = false
    @State private var isReordering = false
    @State private var selectedIds: Set<Int64> = []
    @State private var showBulkDeleteConfirm = false
    @State private var showBulkAddToRun = false

    @State private var selectedPublisher: String = "All"
    @State private var searchText: String = ""

    @State private var selectedSmartFilter: SmartFilter?

    @State private var activeRun: Run?
    @State private var selectedRun: Run?

    @State private var missingFileComic: Comic?

    enum SmartFilter: String, CaseIterable {
        case recentlyAdded = "New"
        case inProgress    = "In Progress"
        case unread        = "Unread"
        case finished      = "Finished"
    }

    private var phoneColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 130), spacing: .arcS12)]
    }

    private var ipadColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 180), spacing: .arcS16)]
    }

    private var columns: [GridItem] {
        sizeClass == .regular ? ipadColumns : phoneColumns
    }

    private var isSearching: Bool { !searchText.isEmpty }

    private var displayedComics: [Comic] {
        guard let filter = selectedSmartFilter else { return library.comics }
        switch filter {
        case .recentlyAdded:
            let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            return library.comics.filter { $0.dateAdded >= cutoff }
        case .inProgress:
            return library.comics.filter { $0.isStarted && !$0.isFinished }
        case .unread:
            return library.comics.filter { !$0.isStarted }
        case .finished:
            return library.comics.filter { $0.isFinished }
        }
    }

    var body: some View {
        NavigationStack {
            Group {

                if sizeClass == .regular && !isSearching {
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
            }
            .task(id: searchText) {
                if !searchText.isEmpty {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    guard !Task.isCancelled else { return }
                }
                reload()
            }
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) {
                if isSelecting { bulkActionsToolbar }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [
                    UTType("com.comicarcapp.cbz") ?? .zip,
                    UTType("com.comicarcapp.cbr") ?? .data,
                    .pdf, .jpeg, .png
                ],
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
            .onAppear { reload(); loadActiveRun() }
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
                "Move \(selectedIds.count) comic\(selectedIds.count == 1 ? "" : "s") to Trash?",
                isPresented: $showBulkDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Move to Trash", role: .destructive) { bulkDelete() }
            }
            .sheet(isPresented: $showBulkAddToRun) {
                BulkAddToRunSheet(comicIds: Array(selectedIds)) { exitSelection() }
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

    private var ipadCharacterBrowse: some View {
        HStack(alignment: .top, spacing: 0) {

            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if library.importProgress.isActive {
                            importBanner.padding(.horizontal, 12).padding(.top, 8)
                        }
                        if !library.publishers.isEmpty {
                            publisherFilterRow.padding(.horizontal, 12)
                        }
                        if !library.recentlyAdded.isEmpty {
                            recentlyAddedSection.padding(.horizontal, 12)
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

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if selectedSeries != nil {
                        ipadIssuePanel
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

    private var ipadIssuePanel: some View {
        VStack(alignment: .leading, spacing: 0) {

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

            if displayedComics.isEmpty {
                EmptyStateView(
                    icon: "books.vertical",
                    title: "No Issues",
                    message: selectedSmartFilter.map { "No issues match the \"\($0.rawValue)\" filter." }
                        ?? "No issues found for this series."
                )
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: ipadColumns, spacing: .arcS16) {
                    ForEach(displayedComics) { comic in
                        selectableComicCard(comic)
                    }
                }
                .padding()
            }
        }
    }

    private var phoneScrollContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if library.importProgress.isActive { importBanner }

                if !library.publishers.isEmpty && !isSearching {
                    publisherFilterRow
                }

                if isSearching {
                    smartFilterRow
                    searchResultsGrid
                } else {
                    if selectedCharacter != nil { breadcrumbBar }
                    if let series = selectedSeries {
                        issueGrid(series: series)
                    } else if let char = selectedCharacter {
                        seriesGrid(character: char)
                    } else {
                        smartFilterRow
                        if !library.recentlyAdded.isEmpty { recentlyAddedSection }
                        if !library.inProgress.isEmpty { continueReadingSection }
                        continueRunSection
                        characterGrid
                    }
                }
            }
            .padding(.horizontal)
        }
    }

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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if isSelecting {
                Button {
                    let allIds = Set(displayedComics.map(\.id))
                    withAnimation {
                        selectedIds = (selectedIds == allIds) ? [] : allIds
                    }
                } label: {
                    Text(selectedIds.count == displayedComics.count && !displayedComics.isEmpty
                         ? "None" : "All")
                        .font(.subheadline)
                }
                .accessibilityLabel("Select all or deselect all")
            } else if isReordering {
                Button("Done") {
                    withAnimation { isReordering = false }
                }
            } else {
                if selectedSeries != nil && !isSearching {
                    Button {
                        withAnimation { isReordering = true }
                        reloadIssues(sortOrder: .manual)
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                    .accessibilityLabel("Reorder issues")
                }

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
            } else if isReordering {
                EmptyView()
            } else if !isSearching && (selectedSeries != nil || selectedCharacter != nil) {
                Button {
                    withAnimation {
                        isReordering = false
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

    private var recentlyAddedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recently Added").font(.headline).padding(.top, 16)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(library.recentlyAdded) { comic in
                        VStack(alignment: .leading, spacing: 4) {
                            CoverImage(comic: comic)
                                .frame(width: 80, height: 116)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Text(comic.title)
                                .font(.caption2).lineLimit(2)
                                .frame(width: 80, alignment: .leading)
                        }
                        .onTapGesture { detailComic = comic }
                    }
                }
            }
        }
        .padding(.bottom, 16)
    }

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

    @State private var seriesDescription: String = ""

    private func issueGrid(series: SeriesGroup) -> some View {
        VStack(spacing: 0) {
            if !seriesDescription.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "text.quote")
                        .font(.caption)
                        .foregroundStyle(Color.arcGold)
                        .padding(.top, 1)
                    Text(seriesDescription)
                        .font(.caption)
                        .foregroundStyle(Color.arcMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.arcSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.arcBorder, lineWidth: 1))
                .padding(.bottom, 8)
            }

            smartFilterRow

            if isReordering {
                List {
                    ForEach(library.comics) { comic in
                        ManualSortRow(comic: comic)
                            .listRowBackground(Color.arcCard)
                            .listRowSeparatorTint(Color.arcBorder)
                    }
                    .onMove { from, to in
                        var reordered = library.comics
                        reordered.move(fromOffsets: from, toOffset: to)
                        let updates = reordered.enumerated().map { (id: $0.element.id, sortOrder: $0.offset) }
                        library.updateSortOrders(updates)
                    }
                }
                .environment(\.editMode, .constant(.active))
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .frame(minHeight: CGFloat(library.comics.count) * 72)
            } else if displayedComics.isEmpty {
                issueEmptyState
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: .arcS16) {
                    ForEach(displayedComics) { comic in
                        selectableComicCard(comic)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private var issueEmptyState: some View {
        if let filter = selectedSmartFilter {
            switch filter {
            case .recentlyAdded:
                EmptyStateView(icon: "clock", title: "Nothing Added Recently",
                               message: "Comics added in the last 30 days will appear here.")
            case .inProgress:
                EmptyStateView(icon: "book.fill", title: "Nothing In Progress",
                               message: "Open any comic to start reading.")
            case .unread:
                EmptyStateView(icon: "checkmark.circle", title: "No Unread Issues",
                               message: "Everything in this series has been started.")
            case .finished:
                EmptyStateView(icon: "trophy", title: "No Finished Issues Yet",
                               message: "Read to the last page of any issue to see it here.")
            }
        } else {
            EmptyStateView(icon: "books.vertical", title: "No Issues",
                           message: "No issues found for this series.")
        }
    }

    private var searchResultsGrid: some View {
        Group {
            if displayedComics.isEmpty {
                EmptyStateView(
                    icon: "magnifyingglass",
                    title: "No Results for \"\(searchText)\"",
                    message: "Try searching by title or series name."
                )
                .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: .arcS16) {
                    ForEach(displayedComics) { comic in
                        selectableComicCard(comic)
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var navigationTitle: String {
        if isSearching          { return "Search Results" }
        if let s = selectedSeries  { return s.groupName }
        if let c = selectedCharacter { return c.groupName }
        return "Library"
    }

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

    @ViewBuilder
    private var continueRunSection: some View {
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

                    Button { bulkMarkUnread() } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.counterclockwise").font(.title3)
                            Text("Unread").font(.system(size: 9))
                        }
                    }
                    .accessibilityLabel("Mark selected as unread")

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

                    Button { showBulkAddToRun = true } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "list.number").font(.title3)
                            Text("Run").font(.system(size: 9))
                        }
                    }
                    .accessibilityLabel("Add selected to reading run")

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

    private func selectCharacter(_ group: SeriesGroup) {
        selectedSmartFilter = nil
        isReordering = false
        selectedCharacter = group
        selectedSeries = nil
        seriesDescription = ""
        let pub = selectedPublisher == "All" ? nil : selectedPublisher
        if group.character != nil {
            library.loadSeries(for: group.groupName, publisher: pub)
        } else {
            selectedSeries = group
            library.loadIssues(character: nil, series: group.groupName, publisher: pub)
        }
    }

    private func selectSeries(_ group: SeriesGroup) {
        selectedSmartFilter = nil
        isReordering = false
        selectedSeries = group
        seriesDescription = ""
        let pub = selectedPublisher == "All" ? nil : selectedPublisher
        library.loadIssues(
            character: selectedCharacter?.character,
            series: group.groupName,
            publisher: pub
        )
        Task.detached(priority: .utility) { [pub] in
            let meta = DatabaseManager.shared.seriesMeta(
                publisher: pub ?? group.publisher,
                series: group.groupName
            )
            let desc = meta?.description ?? ""
            await MainActor.run { seriesDescription = desc }
        }
    }

    private func reloadIssues(sortOrder: DatabaseManager.SortOrder = .publisher) {
        guard let series = selectedSeries else { return }
        let pub = selectedPublisher == "All" ? nil : selectedPublisher
        library.loadIssues(
            character: selectedCharacter?.character,
            series: series.groupName,
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

    private func toggleSelection(_ id: Int64) {
        if selectedIds.contains(id) { selectedIds.remove(id) } else { selectedIds.insert(id) }
    }

    private func exitSelection() {
        withAnimation(.easeInOut(duration: 0.2)) { isSelecting = false; selectedIds.removeAll() }
    }

    private func reload() {
        let pub = selectedPublisher == "All" ? nil : selectedPublisher
        library.load(
            publisher: pub,
            search: searchText.isEmpty ? nil : searchText
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

    private func bulkMarkUnread() {
        let mutations: [LibraryMutation] = library.comics
            .filter { selectedIds.contains($0.id) }
            .map { .setProgress(id: $0.id, page: 0) }
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

struct SeriesCard: View {
    let group: SeriesGroup
    var characterName: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            ZStack(alignment: .topTrailing) {
                ZStack(alignment: .bottom) {
                    CoverImage(comicId: group.coverComicId)
                        .aspectRatio(2/3, contentMode: .fill)
                        .clipped()
                    if group.issueCount > 0 && group.completed > 0 {
                        Rectangle()
                            .fill(group.isFinished ? Color.green : Color.arcGold)
                            .frame(height: 3)
                            .scaleEffect(x: CGFloat(group.completed) / CGFloat(group.issueCount), y: 1, anchor: .leading)
                    }
                }
                if group.isFinished {
                    badge("Done", color: .green)
                } else if group.isReading {
                    badge("Reading", color: .arcBlue)
                }
            }

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

struct ManualSortRow: View {
    let comic: Comic

    var body: some View {
        HStack(spacing: 12) {
            CoverImage(comic: comic)
                .frame(width: 40, height: 57)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            VStack(alignment: .leading, spacing: 3) {
                Text(comic.title)
                    .font(.subheadline)
                    .lineLimit(2)
                Text(comic.series)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if comic.pageCount > 0 && comic.isStarted {
                    ArcProgressBar(value: comic.progressPercent)
                        .frame(maxWidth: 100)
                }
            }

            Spacer()

            if comic.isFinished {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }
}

struct BulkAddToRunSheet: View {
    @Environment(\.dismiss) private var dismiss
    let comicIds: [Int64]
    let onDone: () -> Void

    @State private var runs: [Run] = []
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            List {
                if runs.isEmpty {
                    Text("No runs yet. Create one first.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(runs) { run in
                        Button {
                            addAll(to: run)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(run.title).font(.subheadline).foregroundStyle(.white)
                                    Text("\(run.itemCount) issue\(run.itemCount == 1 ? "" : "s")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(Color.arcGold)
                            }
                        }
                        .listRowBackground(Color.arcCard)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.arcBg)
            .navigationTitle("Add \(comicIds.count) Comic\(comicIds.count == 1 ? "" : "s") to Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreate, onDismiss: load) {
                CreateRunView()
            }
            .onAppear { load() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func load() {
        runs = DatabaseManager.shared.allRuns()
    }

    private func addAll(to run: Run) {
        let runId = run.id
        let ids = comicIds
        Task {
            await Task.detached(priority: .userInitiated) {
                for id in ids {
                    DatabaseManager.shared.addToRun(runId: runId, comicId: id)
                }
            }.value
        }
        onDone()
        dismiss()
    }
}
