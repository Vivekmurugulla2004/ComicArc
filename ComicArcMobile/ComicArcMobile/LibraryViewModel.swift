import Foundation
import SwiftUI

@MainActor
final class LibraryViewModel: ObservableObject {
    @Published var comics: [Comic] = []
    @Published var runs: [ReadingRun] = []
    @Published var isScanning = false
    @Published var scanProgress: (done: Int, total: Int) = (0, 0)

    private let comicsKey = "comicarc.comics"
    private let runsKey   = "comicarc.runs"

    init() { load() }

    // MARK: - Persistence

    func load() {
        comics = decode([Comic].self, from: UserDefaults.standard.data(forKey: comicsKey)) ?? []
        runs   = decode([ReadingRun].self, from: UserDefaults.standard.data(forKey: runsKey)) ?? []
    }

    private func save() {
        UserDefaults.standard.set(encode(comics), forKey: comicsKey)
        UserDefaults.standard.set(encode(runs),   forKey: runsKey)
    }

    private func encode<T: Encodable>(_ value: T) -> Data? {
        try? JSONEncoder().encode(value)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    // MARK: - Import

    func importFiles(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isScanning = true
        scanProgress = (0, urls.count)
        Task.detached(priority: .userInitiated) { [urls] in
            var added: [Comic] = []
            for (i, url) in urls.enumerated() {
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }

                let ext = url.pathExtension.lowercased()
                guard ["cbz", "cbr", "pdf", "jpg", "jpeg", "png"].contains(ext) else {
                    await MainActor.run { self.scanProgress.done = i + 1 }
                    continue
                }

                // Skip duplicates by path
                let path = url.path
                let alreadyExists = await MainActor.run { self.comics.contains { $0.filePath == path } }
                if alreadyExists {
                    await MainActor.run { self.scanProgress.done = i + 1 }
                    continue
                }

                let bookmark = try? url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                let pageCount = ComicReader.pageCount(url: url)
                let ci = ComicReader.comicInfo(url: url)

                var comic = Comic(
                    title:      ci?.series.map { "\($0)" } ?? url.deletingPathExtension().lastPathComponent,
                    series:     ci?.series ?? "General",
                    publisher:  ci?.publisher ?? "Unknown",
                    issueNumber: ci?.issueNumber,
                    pageCount:  pageCount,
                    filePath:   path,
                    bookmarkData: bookmark
                )
                comic.writer      = ci?.writer
                comic.penciller   = ci?.penciller
                comic.year        = ci?.year
                comic.storyArc    = ci?.storyArc
                comic.languageISO = ci?.languageISO
                // Better title from filename if ComicInfo didn't have one
                if ci == nil {
                    comic.title = url.deletingPathExtension().lastPathComponent
                }
                added.append(comic)
                await MainActor.run { self.scanProgress.done = i + 1 }
            }
            await MainActor.run {
                self.comics.append(contentsOf: added)
                self.save()
                self.isScanning = false
            }
        }
    }

    func loadCollections() { load() }

    // MARK: - Queries

    func continueReading() -> [Comic] {
        comics.filter { $0.isStarted && !$0.isFinished }
            .sorted { ($0.lastRead ?? .distantPast) > ($1.lastRead ?? .distantPast) }
            .prefix(5)
            .map { $0 }
    }

    func favorites() -> [Comic] {
        comics.filter(\.isFavorite).sorted { $0.title < $1.title }
    }

    func inReadingList() -> [Comic] {
        comics.filter(\.inReadingList).sorted { $0.addedAt > $1.addedAt }
    }

    func comics(forTag tag: String) -> [Comic] {
        []  // Tags not yet stored per-comic on iOS
    }

    func nextInSeries(after comic: Comic) -> Comic? {
        let series = comics.filter { $0.series == comic.series && $0.publisher == comic.publisher && $0.id != comic.id }
            .sorted { naturalSort($0.issueNumber ?? "") < naturalSort($1.issueNumber ?? "") }
        guard let idx = series.firstIndex(where: { $0.id == comic.id }),
              idx + 1 < series.count else {
            return series.first
        }
        return series[idx + 1]
    }

    func stats() -> LibraryStats {
        let completed  = comics.filter(\.isFinished).count
        let inProgress = comics.filter { $0.isStarted && !$0.isFinished }.count
        let pagesRead  = comics.reduce(0) { $0 + $1.currentPage }
        let favs       = comics.filter(\.isFavorite).count
        let pubMap     = Dictionary(grouping: comics, by: \.publisher).mapValues(\.count)
        let byPub      = pubMap.sorted { $0.value > $1.value }.map { (publisher: $0.key, count: $0.value) }
        let seriesMap  = Dictionary(grouping: comics.filter { $0.series != "General" }, by: \.series).mapValues(\.count)
        let topSeries  = seriesMap.sorted { $0.value > $1.value }.prefix(8).map { (series: $0.key, count: $0.value) }
        let recent     = comics.filter { $0.lastRead != nil }.sorted { ($0.lastRead ?? .distantPast) > ($1.lastRead ?? .distantPast) }.prefix(6).map { $0 }

        let calendar = Calendar.current
        var activityMap: [String: Int] = [:]
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        for c in comics where c.lastRead != nil {
            let key = fmt.string(from: c.lastRead!)
            activityMap[key, default: 0] += 1
        }

        return LibraryStats(
            total: comics.count, completed: completed, inProgress: inProgress,
            pagesRead: pagesRead, favorites: favs, runs: runs.count,
            byPublisher: byPub, topSeries: Array(topSeries),
            recentReads: Array(recent), activityMap: activityMap
        )
    }

    // MARK: - Mutations

    func saveProgress(id: UUID, page: Int) {
        update(id: id) { $0.currentPage = page; $0.lastRead = Date() }
    }

    func toggleFavorite(id: UUID) {
        update(id: id) { $0.isFavorite.toggle() }
    }

    func toggleReadingList(id: UUID) {
        update(id: id) { $0.inReadingList.toggle() }
    }

    func rate(id: UUID, rating: Int) {
        update(id: id) { $0.rating = rating }
    }

    func markRead(id: UUID) {
        update(id: id) { c in
            c.currentPage = max(c.pageCount - 1, 0)
            c.lastRead = Date()
        }
    }

    func markUnread(id: UUID) {
        update(id: id) { $0.currentPage = 0; $0.lastRead = nil }
    }

    func remove(id: UUID) {
        comics.removeAll { $0.id == id }
        save()
    }

    // MARK: - Runs

    func createRun(title: String, description: String?) {
        runs.append(ReadingRun(title: title, description: description))
        save()
    }

    func deleteRun(id: UUID) {
        runs.removeAll { $0.id == id }
        save()
    }

    func addToRun(runId: UUID, comicId: UUID) {
        guard let idx = runs.firstIndex(where: { $0.id == runId }) else { return }
        if !runs[idx].comicIds.contains(comicId) {
            runs[idx].comicIds.append(comicId)
            save()
        }
    }

    func removeFromRun(runId: UUID, comicId: UUID) {
        guard let idx = runs.firstIndex(where: { $0.id == runId }) else { return }
        runs[idx].comicIds.removeAll { $0 == comicId }
        save()
    }

    func reorderRun(runId: UUID, from source: IndexSet, to destination: Int) {
        guard let idx = runs.firstIndex(where: { $0.id == runId }) else { return }
        runs[idx].comicIds.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func comics(inRun run: ReadingRun) -> [Comic] {
        run.comicIds.compactMap { id in comics.first { $0.id == id } }
    }

    // MARK: - Helpers

    private func update(id: UUID, _ mutation: (inout Comic) -> Void) {
        guard let idx = comics.firstIndex(where: { $0.id == id }) else { return }
        mutation(&comics[idx])
        save()
    }

    private func naturalSort(_ s: String) -> String {
        s.components(separatedBy: .decimalDigits.inverted)
            .compactMap { Int($0) }
            .map { String(format: "%05d", $0) }
            .joined()
            .appending(s)
    }

    func resolvedURL(for comic: Comic) -> URL? {
        if let bookmarkData = comic.bookmarkData {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                return url
            }
        }
        return URL(fileURLWithPath: comic.filePath)
    }
}
