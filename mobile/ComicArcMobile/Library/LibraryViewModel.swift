import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var comics: [Comic] = []
    @Published var inProgress: [Comic] = []
    @Published var characterGroups: [SeriesGroup] = []
    @Published var seriesGroups: [SeriesGroup] = []
    @Published var publishers: [String] = []

    @Published var selectedPublisher: String = "All"
    @Published var searchText: String = ""
    @Published var isImporting = false
    @Published var importError: String?

    private let db = DatabaseManager.shared

    func load() {
        publishers = db.publishers()
        inProgress = db.inProgress()
        characterGroups = db.characterGroups(publisher: selectedPublisher == "All" ? nil : selectedPublisher)
        comics = db.allComics(
            publisher: selectedPublisher == "All" ? nil : selectedPublisher,
            search: searchText.isEmpty ? nil : searchText
        )
    }

    func loadSeries(for character: String) {
        seriesGroups = db.seriesGroups(
            character: character,
            publisher: selectedPublisher == "All" ? nil : selectedPublisher
        )
    }

    func loadIssues(character: String, series: String) {
        comics = db.allComics(
            publisher: selectedPublisher == "All" ? nil : selectedPublisher,
            character: character,
            series: series
        )
    }

    func importFiles(_ urls: [URL]) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            for url in urls {
                await self.importFile(url)
            }
            await MainActor.run { self.load() }
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

        let meta = ComicImporter.parse(url: dest)
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

    func toggleFavorite(_ comic: Comic) {
        db.setFavorite(comic.id, !comic.isFavorite)
        load()
    }

    func setRating(_ comic: Comic, rating: Int) {
        db.setRating(comic.id, rating)
        load()
    }

    func delete(_ comic: Comic) {
        db.deleteComic(comic.id)
        load()
    }

    func updateProgress(_ comic: Comic, page: Int) {
        db.updateProgress(comicId: comic.id, page: page)
    }
}
