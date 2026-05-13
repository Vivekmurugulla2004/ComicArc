import SwiftUI
import Combine

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var comics: [Comic] = []
    @Published var inProgress: [Comic] = []
    @Published var characterGroups: [SeriesGroup] = []
    @Published var seriesGroups: [SeriesGroup] = []
    @Published var publishers: [String] = []
    @Published var allTags: [Tag] = []

    @Published var selectedPublisher: String = "All"
    @Published var sortOrder: DatabaseManager.SortOrder = .publisher
    @Published var searchText: String = ""
    @Published var selectedTag: String?
    @Published var importProgress: (done: Int, total: Int) = (0, 0)
    @Published var importError: String?

    /// Set by ReaderView when user taps "Read Next" in a run — observed by RunDetailView
    @Published var pendingRunComic: Comic?

    private let db = DatabaseManager.shared

    // MARK: - Load

    func load() {
        publishers   = db.publishers()
        inProgress   = db.inProgress()
        allTags      = db.allTags()
        characterGroups = db.characterGroups(
            publisher: selectedPublisher == "All" ? nil : selectedPublisher
        )

        if let tag = selectedTag {
            comics = db.comics(withTag: tag)
        } else {
            comics = db.allComics(
                publisher: selectedPublisher == "All" ? nil : selectedPublisher,
                search: searchText.isEmpty ? nil : searchText,
                sortOrder: sortOrder
            )
        }
    }

    func loadSeries(for character: String) {
        seriesGroups = db.seriesGroups(
            character: character,
            publisher: selectedPublisher == "All" ? nil : selectedPublisher
        )
    }

    func loadIssues(character: String?, series: String) {
        comics = db.allComics(
            publisher: selectedPublisher == "All" ? nil : selectedPublisher,
            character: character,
            series: series,
            nullCharacterOnly: character == nil,
            sortOrder: sortOrder
        )
    }

    func loadSearchResults() {
        guard !searchText.isEmpty else { load(); return }
        comics = db.allComics(
            publisher: selectedPublisher == "All" ? nil : selectedPublisher,
            search: searchText,
            sortOrder: sortOrder
        )
    }

    // MARK: - Import

    func importFiles(_ urls: [URL]) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let count = urls.count
            for (i, url) in urls.enumerated() {
                await MainActor.run { self.importProgress = (i, count) }
                await self.importFile(url)
            }
            await MainActor.run {
                self.importProgress = (0, 0)
                self.load()
            }
        }
    }

    private func importFile(_ source: URL) async {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Comics")
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)

        let dest = docs.appendingPathComponent(source.lastPathComponent)
        if !FileManager.default.fileExists(atPath: dest.path) {
            do {
                try FileManager.default.copyItem(at: source, to: dest)
            } catch {
                await MainActor.run { self.importError = error.localizedDescription }
                return
            }
        }

        let meta      = ComicImporter.parse(url: dest)
        let pageCount = await ComicImporter.pageCount(url: dest)
        db.insertComic(
            title:       meta.title,
            filePath:    dest.path,
            publisher:   meta.publisher,
            character:   meta.character,
            series:      meta.series,
            issueNumber: meta.issueNumber,
            pageCount:   pageCount
        )
    }

    // MARK: - Mutations

    func setRating(_ comic: Comic, rating: Int) {
        db.setRating(comic.id, rating)
        load()
    }

    func delete(_ comic: Comic) {
        let docsPath = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Comics").path
        if comic.filePath.hasPrefix(docsPath) {
            try? FileManager.default.removeItem(atPath: comic.filePath)
        }
        ThumbnailCache.shared.invalidate(comicId: comic.id)
        CBZReaderCache.shared.invalidate(path: comic.filePath)
        db.deleteComic(comic.id)
        load()
    }

    func updateProgress(_ comic: Comic, page: Int) {
        db.updateProgress(comicId: comic.id, page: page)
    }
}
