import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showImporter = false
    @State private var browseMode: BrowseMode = .characters
    @State private var selectedCharacter: SeriesGroup?
    @State private var selectedSeries: SeriesGroup?
    @State private var detailComicId: Int64?
    @State private var continueComicId: Int64?

    enum BrowseMode { case characters, flat }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .regular ? 160 : 140), spacing: 12)]
    }

    // True when user is actively searching — bypass the hierarchy
    private var isSearching: Bool { !library.searchText.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Import progress banner
                    if library.importProgress.total > 0 {
                        importBanner
                    }

                    // Publisher filter tabs
                    if !library.publishers.isEmpty && !isSearching {
                        publisherFilterRow
                    }

                    // Tag filter chips (only in flat / search mode)
                    if (browseMode == .flat || isSearching) && !library.allTags.isEmpty {
                        tagFilterRow
                    }

                    // Search results bypass the hierarchy
                    if isSearching {
                        flatGrid
                    } else if browseMode == .characters {
                        if let series = selectedSeries {
                            issueGrid(series: series)
                        } else if let char = selectedCharacter {
                            seriesGrid(character: char)
                        } else {
                            // Continue Reading
                            if !library.inProgress.isEmpty { continueReadingSection }
                            characterGrid
                        }
                    } else {
                        if !library.inProgress.isEmpty && library.selectedTag == nil {
                            continueReadingSection
                        }
                        flatGrid
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle(navigationTitle)
            .background(Color.arcBg)
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $library.searchText, prompt: "Search comics")
            .onChange(of: library.searchText) { _, _ in
                if isSearching {
                    library.loadSearchResults()
                } else {
                    library.load()
                }
            }
            .toolbar { toolbarContent }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.init(filenameExtension: "cbz")!,
                                      .init(filenameExtension: "cbr")!,
                                      .pdf, .jpeg, .png],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result { library.importFiles(urls) }
            }
            .onAppear { library.load() }
            .sheet(item: Binding(
                get: { detailComicId.map { LibID($0) } },
                set: { detailComicId = $0?.id }
            )) { w in
                ComicDetailView(comicId: w.id)
                    .environmentObject(library)
            }
            .sheet(item: Binding(
                get: { continueComicId.map { LibID($0) } },
                set: { continueComicId = $0?.id }
            )) { w in
                if let comic = DatabaseManager.shared.comic(id: w.id) {
                    ReaderView(comic: comic)
                        .environmentObject(library)
                        .onDisappear { library.load() }
                }
            }
            .alert("Import Error", isPresented: Binding(
                get: { library.importError != nil },
                set: { if !$0 { library.importError = nil } }
            )) {
                Button("OK", role: .cancel) { library.importError = nil }
            } message: {
                Text(library.importError ?? "")
            }
        }
    }

    // MARK: - Import Banner

    private var importBanner: some View {
        HStack {
            ProgressView()
            Text("Importing \(library.importProgress.done + 1) of \(library.importProgress.total)…")
                .font(.subheadline)
            Spacer()
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
                publisherChip("All", isActive: library.selectedPublisher == "All") {
                    library.selectedPublisher = "All"
                    library.load()
                }
                ForEach(library.publishers, id: \.self) { pub in
                    publisherChip(pub, isActive: library.selectedPublisher == pub) {
                        library.selectedPublisher = (library.selectedPublisher == pub) ? "All" : pub
                        library.load()
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func publisherChip(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.bold())
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isActive ? Color.arcGold : Color.arcSurface)
                .foregroundStyle(isActive ? Color.arcBg : Color.primary)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.arcBorder, lineWidth: isActive ? 0 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tag Filter Row

    private var tagFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                tagChip("All", isActive: library.selectedTag == nil) {
                    library.selectedTag = nil
                    library.load()
                }
                ForEach(library.allTags) { tag in
                    tagChip(tag.name, isActive: library.selectedTag == tag.name) {
                        library.selectedTag = (library.selectedTag == tag.name) ? nil : tag.name
                        library.load()
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func tagChip(_ label: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isActive ? Color.arcGold : Color.arcSurface)
                .foregroundStyle(isActive ? .white : .primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if !isSearching {
                Picker("", selection: $browseMode) {
                    Image(systemName: "square.grid.2x2").tag(BrowseMode.characters)
                    Image(systemName: "list.bullet").tag(BrowseMode.flat)
                }
                .pickerStyle(.segmented)
                .frame(width: 80)

                Menu {
                    ForEach(DatabaseManager.SortOrder.allCases, id: \.self) { order in
                        Button {
                            library.sortOrder = order
                            library.load()
                        } label: {
                            Label(order.rawValue,
                                  systemImage: library.sortOrder == order ? "checkmark" : "")
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
            }
            Button { showImporter = true } label: {
                Image(systemName: "plus")
            }
        }
        if !isSearching && (selectedSeries != nil || selectedCharacter != nil) {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    withAnimation {
                        if selectedSeries != nil { selectedSeries = nil }
                        else { selectedCharacter = nil }
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
                            .onTapGesture { continueComicId = comic.id }
                    }
                }
            }
        }
        .padding(.bottom, 16)
    }

    // MARK: - Grids

    private var characterGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(library.characterGroups) { group in
                SeriesCard(group: group)
                    .onTapGesture {
                        withAnimation {
                            selectedCharacter = group
                            library.loadSeries(for: group.groupName)
                        }
                    }
            }
        }
        .padding(.top, 8)
    }

    private func seriesGrid(character: SeriesGroup) -> some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(library.seriesGroups) { group in
                SeriesCard(group: group)
                    .onTapGesture {
                        withAnimation {
                            selectedSeries = group
                            library.loadIssues(character: character.groupName, series: group.groupName)
                        }
                    }
            }
        }
        .padding(.top, 8)
    }

    private func issueGrid(series: SeriesGroup) -> some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(library.comics) { comic in
                ComicCard(comic: comic)
                    .onTapGesture { detailComicId = comic.id }
            }
        }
        .padding(.top, 8)
    }

    private var flatGrid: some View {
        Group {
            if library.comics.isEmpty && !library.searchText.isEmpty {
                ContentUnavailableView.search(text: library.searchText)
                    .padding(.top, 60)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(library.comics) { comic in
                        ComicCard(comic: comic)
                            .onTapGesture { detailComicId = comic.id }
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
        if let t = library.selectedTag        { return t }
        return "Library"
    }
}

// Identifiable wrapper
private struct LibID: Identifiable {
    let id: Int64
    init(_ id: Int64) { self.id = id }
}

// MARK: - Continue Card

struct ContinueCard: View {
    let comic: Comic

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CoverImage(comicId: comic.id)
                .frame(width: 90, height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(alignment: .bottom) {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color.arcGold)
                            .frame(width: geo.size.width * comic.progressPercent, height: 3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }
            Text(comic.title)
                .font(.caption2).lineLimit(2)
                .frame(width: 90, alignment: .leading)
            if comic.pageCount > 0 {
                Text("p.\(comic.progress)/\(comic.pageCount)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Series Card

struct SeriesCard: View {
    let group: SeriesGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                CoverImage(comicId: group.coverComicId)
                    .aspectRatio(2/3, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                if group.isFinished {
                    badge("Done", color: .green)
                } else if group.isReading {
                    badge("Reading", color: .arcGold)
                }
            }
            Text(group.groupName)
                .font(.subheadline).fontWeight(.semibold).lineLimit(2)
            Text("\(group.issueCount) issue\(group.issueCount == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func badge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2).fontWeight(.bold)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color).foregroundStyle(.white)
            .clipShape(Capsule()).padding(4)
    }
}
