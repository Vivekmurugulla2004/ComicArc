import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var library: LibraryViewModel
    @State private var showImporter = false
    @State private var browseMode: BrowseMode = .characters
    @State private var selectedCharacter: SeriesGroup?
    @State private var selectedSeries: SeriesGroup?
    @State private var detailComicId: Int64?  // push detail sheet
    @State private var continueComicId: Int64? // direct to reader from Continue shelf

    enum BrowseMode { case characters, flat }

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if browseMode == .characters,
                       selectedCharacter == nil,
                       !library.inProgress.isEmpty {
                        continueReadingSection
                    }

                    if browseMode == .characters {
                        if let series = selectedSeries {
                            issueGrid(series: series)
                        } else if let char = selectedCharacter {
                            seriesGrid(character: char)
                        } else {
                            characterGrid
                        }
                    } else {
                        flatGrid
                    }
                }
                .padding(.horizontal)
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $library.searchText, prompt: "Search comics")
            .onChange(of: library.searchText) { _ in library.load() }
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
            // Detail sheet — tapping a comic card
            .sheet(item: Binding(
                get: { detailComicId.map { AnyID($0) } },
                set: { detailComicId = $0?.id }
            )) { wrapper in
                ComicDetailView(comicId: wrapper.id)
                    .environmentObject(library)
            }
            // Direct reader — tapping Continue Reading
            .sheet(item: Binding(
                get: { continueComicId.map { AnyID($0) } },
                set: { continueComicId = $0?.id }
            )) { wrapper in
                if let comic = DatabaseManager.shared.comic(id: wrapper.id) {
                    ReaderView(comic: comic)
                        .environmentObject(library)
                        .onDisappear { library.load() }
                }
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Picker("", selection: $browseMode) {
                Image(systemName: "square.grid.2x2").tag(BrowseMode.characters)
                Image(systemName: "list.bullet").tag(BrowseMode.flat)
            }
            .pickerStyle(.segmented)
            .frame(width: 80)

            Button { showImporter = true } label: {
                Image(systemName: "plus")
            }
        }
        if selectedSeries != nil || selectedCharacter != nil {
            ToolbarItem(placement: .navigationBarLeading) {
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
            Text("Continue Reading")
                .font(.headline)
                .padding(.top, 16)

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
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(library.comics) { comic in
                ComicCard(comic: comic)
                    .onTapGesture { detailComicId = comic.id }
            }
        }
        .padding(.top, 8)
    }

    private var navigationTitle: String {
        if let s = selectedSeries   { return s.groupName }
        if let c = selectedCharacter { return c.groupName }
        return "Library"
    }
}

// Identifiable wrapper so .sheet(item:) works with Int64
private struct AnyID: Identifiable {
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
                            .fill(Color.orange)
                            .frame(width: geo.size.width * comic.progressPercent, height: 3)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    }
                }

            Text(comic.title)
                .font(.caption2)
                .lineLimit(2)
                .frame(width: 90, alignment: .leading)

            if comic.pageCount > 0 {
                Text("p.\(comic.progress)/\(comic.pageCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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
                    badge("Reading", color: .orange)
                }
            }

            Text(group.groupName)
                .font(.subheadline).fontWeight(.semibold)
                .lineLimit(2)

            Text("\(group.issueCount) issue\(group.issueCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func badge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2).fontWeight(.bold)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color)
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .padding(4)
    }
}
