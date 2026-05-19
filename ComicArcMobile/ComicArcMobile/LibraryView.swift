import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var search = ""
    @State private var publisherFilter = "All"
    @State private var statusFilter   = "All"
    @State private var detailComic: Comic?
    @State private var showPicker = false

    private var publishers: [String] {
        let all = Set(library.comics.map(\.publisher)).sorted()
        return ["All"] + all
    }

    private var filtered: [Comic] {
        library.comics.filter { comic in
            let matchesSearch = search.isEmpty
                || comic.title.localizedCaseInsensitiveContains(search)
                || comic.series.localizedCaseInsensitiveContains(search)
                || comic.publisher.localizedCaseInsensitiveContains(search)
            let matchesPub = publisherFilter == "All" || comic.publisher == publisherFilter
            let matchesStatus: Bool
            switch statusFilter {
            case "Unread":      matchesStatus = !comic.isStarted
            case "In Progress": matchesStatus = comic.isStarted && !comic.isFinished
            case "Finished":    matchesStatus = comic.isFinished
            default:            matchesStatus = true
            }
            return matchesSearch && matchesPub && matchesStatus
        }
        .sorted { $0.publisher == $1.publisher
            ? ($0.series == $1.series ? $0.title < $1.title : $0.series < $1.series)
            : $0.publisher < $1.publisher }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: sizeClass == .regular ? 160 : 130), spacing: .arcS12)]
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Color.arcBg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        continueReadingSection
                        filterBar
                        if filtered.isEmpty {
                            EmptyStateView(
                                icon: "books.vertical",
                                title: library.comics.isEmpty ? "No Comics Yet" : "No Results",
                                message: library.comics.isEmpty
                                    ? "Tap + to import your first comic."
                                    : "Try a different filter or search.",
                                actionTitle: library.comics.isEmpty ? "Add Comics" : nil,
                                action: library.comics.isEmpty ? { showPicker = true } : nil
                            )
                        } else {
                            LazyVGrid(columns: columns, spacing: .arcS12) {
                                ForEach(filtered) { comic in
                                    ComicCard(comic: comic)
                                        .onTapGesture { detailComic = comic }
                                }
                            }
                            .padding(.horizontal, .arcS16)
                            .padding(.bottom, 100)
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $search, prompt: "Search comics, series…")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showPicker = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $detailComic) { comic in
                ComicDetailView(comic: comic)
                    .environmentObject(library)
            }
            .fileImporter(
                isPresented: $showPicker,
                allowedContentTypes: [
                    UTType(filenameExtension: "cbz") ?? .data,
                    UTType(filenameExtension: "cbr") ?? .data,
                    .pdf, .image
                ],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result { library.importFiles(urls) }
            }
            .overlay {
                if library.isScanning {
                    scanOverlay
                }
            }
        }
    }

    // MARK: - Continue Reading

    @ViewBuilder
    private var continueReadingSection: some View {
        let inProgress = library.continueReading()
        if !inProgress.isEmpty && search.isEmpty && publisherFilter == "All" && statusFilter == "All" {
            VStack(alignment: .leading, spacing: .arcS8) {
                Text("Continue Reading")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, .arcS16)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: .arcS12) {
                        ForEach(inProgress) { comic in
                            ContinueCard(comic: comic)
                                .onTapGesture { detailComic = comic }
                        }
                    }
                    .padding(.horizontal, .arcS16)
                }
            }
            .padding(.top, .arcS16)
            .padding(.bottom, .arcS12)
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .arcS8) {
                ForEach(["All", "Unread", "In Progress", "Finished"], id: \.self) { s in
                    FilterChip(label: s, isActive: statusFilter == s, style: .filled) {
                        statusFilter = s
                    }
                }
                Divider().frame(height: 20).foregroundStyle(Color.arcBorder)
                ForEach(publishers, id: \.self) { pub in
                    FilterChip(label: pub, isActive: publisherFilter == pub, style: .outlined) {
                        publisherFilter = pub
                    }
                }
            }
            .padding(.horizontal, .arcS16)
            .padding(.vertical, .arcS8)
        }
    }

    // MARK: - Scan overlay

    private var scanOverlay: some View {
        VStack(spacing: .arcS8) {
            ProgressView()
                .tint(Color.arcGold)
            Text("Importing \(library.scanProgress.done)/\(library.scanProgress.total)…")
                .font(.caption)
                .foregroundStyle(Color.arcMuted)
        }
        .padding(.arcS16)
        .arcCard()
        .padding(.bottom, 80)
    }
}

struct ContinueCard: View {
    @EnvironmentObject var library: LibraryViewModel
    let comic: Comic

    var body: some View {
        VStack(alignment: .leading, spacing: .arcS4) {
            CoverImage(comic: comic)
                .frame(width: 90, height: 130)
                .clipShape(RoundedRectangle(cornerRadius: .arcInnerRadius))
                .overlay(alignment: .bottom) {
                    ArcProgressBar(value: comic.progress)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                }
            Text(comic.title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .frame(width: 90, alignment: .leading)
            if comic.pageCount > 0 {
                Text("p.\(comic.currentPage)/\(comic.pageCount)")
                    .font(.system(size: 9))
                    .foregroundStyle(Color.arcMuted)
            }
        }
    }
}
