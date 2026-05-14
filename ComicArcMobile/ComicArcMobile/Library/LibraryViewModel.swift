import SwiftUI
import Combine

struct ImportProgress {
    var done: Int = 0
    var total: Int = 0
    var currentFile: String = ""
    var failures: Int = 0
    var isScanning: Bool = false
    var isActive: Bool { total > 0 || isScanning }
}

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
    @Published var importProgress = ImportProgress()
    @Published var importError: String?

    /// Set by ReaderView when user taps "Read Next" in a run — observed by RunDetailView
    @Published var pendingRunComic: Comic?

    private let db = DatabaseManager.shared
    private var importTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?

    // MARK: - Load

    func load() {
        let pub  = selectedPublisher == "All" ? nil : selectedPublisher
        let tag  = selectedTag
        let q    = searchText.isEmpty ? nil : searchText
        let sort = sortOrder
        let db   = db

        Task.detached(priority: .userInitiated) { [weak self] in
            let publishers      = db.publishers()
            let inProgress      = db.inProgress()
            let allTags         = db.allTags()
            let characterGroups = db.characterGroups(publisher: pub)
            let comics: [Comic] = tag != nil
                ? db.comics(withTag: tag!)
                : db.allComics(publisher: pub, search: q, sortOrder: sort)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.publishers      = publishers
                self.inProgress      = inProgress
                self.allTags         = allTags
                self.characterGroups = characterGroups
                self.comics          = comics
            }
        }
    }

    func loadSeries(for character: String) {
        let pub = selectedPublisher == "All" ? nil : selectedPublisher
        let db  = db
        Task.detached(priority: .userInitiated) { [weak self] in
            let groups = db.seriesGroups(character: character, publisher: pub)
            guard let self else { return }
            await MainActor.run { self.seriesGroups = groups }
        }
    }

    func loadIssues(character: String?, series: String) {
        let pub  = selectedPublisher == "All" ? nil : selectedPublisher
        let sort = sortOrder
        let db   = db
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = db.allComics(
                publisher: pub, character: character, series: series,
                nullCharacterOnly: character == nil, sortOrder: sort
            )
            guard let self else { return }
            await MainActor.run { self.comics = result }
        }
    }

    func loadSearchResults() {
        guard !searchText.isEmpty else { load(); return }
        let pub  = selectedPublisher == "All" ? nil : selectedPublisher
        let q    = searchText
        let sort = sortOrder
        let db   = db
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = db.allComics(publisher: pub, search: q, sortOrder: sort)
            guard let self else { return }
            await MainActor.run { self.comics = result }
        }
    }

    func refreshInProgress() {
        let db = db
        Task.detached(priority: .utility) { [weak self] in
            let result = db.inProgress()
            guard let self else { return }
            await MainActor.run { self.inProgress = result }
        }
    }

    // MARK: - Import

    func cancelImport() {
        importTask?.cancel()
        importTask = nil
        importProgress = ImportProgress()
    }

    func importFiles(_ urls: [URL]) {
        importTask?.cancel()
        importProgress = ImportProgress(done: 0, total: urls.count, currentFile: "", failures: 0)
        importTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var failures = 0
            for (i, url) in urls.enumerated() {
                guard !Task.isCancelled else { break }
                let name = url.lastPathComponent
                await MainActor.run {
                    self.importProgress.done        = i
                    self.importProgress.currentFile = name
                }
                let ok = await self.importFile(url)
                if !ok { failures += 1 }
                let f = failures
                await MainActor.run { self.importProgress.failures = f }
            }
            await MainActor.run {
                self.importProgress = ImportProgress()
                self.load()
            }
        }
    }

    func importFolder(_ folderURL: URL) {
        importTask?.cancel()
        importProgress = ImportProgress(isScanning: true)
        importTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let accessing = folderURL.startAccessingSecurityScopedResource()
            defer { if accessing { folderURL.stopAccessingSecurityScopedResource() } }

            let supported = Set(["cbz", "cbr", "pdf", "jpg", "jpeg", "png"])
            guard let enumerator = FileManager.default.enumerator(
                at: folderURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            var files: [URL] = []
            while let fileURL = enumerator.nextObject() as? URL {
                guard !Task.isCancelled else { return }
                if supported.contains(fileURL.pathExtension.lowercased()) {
                    files.append(fileURL)
                }
            }
            files.sort { $0.path < $1.path }

            let fileCount = files.count
            await MainActor.run {
                self.importProgress = ImportProgress(done: 0, total: fileCount,
                                                     currentFile: "", failures: 0)
            }

            var failures = 0
            for (i, fileURL) in files.enumerated() {
                guard !Task.isCancelled else { break }
                let name = fileURL.lastPathComponent
                await MainActor.run {
                    self.importProgress.done        = i
                    self.importProgress.currentFile = name
                }
                let ok = await self.importFileFromFolder(fileURL, folderRoot: folderURL)
                if !ok { failures += 1 }
                let f = failures
                await MainActor.run { self.importProgress.failures = f }
            }

            await MainActor.run {
                self.importProgress = ImportProgress()
                self.load()
            }
        }
    }

    // MARK: - Private import helpers

    private func importFileFromFolder(_ source: URL, folderRoot: URL) async -> Bool {
        if source.pathExtension.lowercased() == "cbr" {
            var rel = source.path
            let rootPath = folderRoot.path
            if rel.hasPrefix(rootPath) {
                rel = String(rel.dropFirst(rootPath.count))
                while rel.hasPrefix("/") { rel = String(rel.dropFirst()) }
            } else {
                rel = source.lastPathComponent
            }
            let relDir = URL(fileURLWithPath: rel).deletingPathExtension().path + ".cbr"
            return await importCBR(source, relativePathHint: relDir)
        }

        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Comics")

        var relative = source.path
        let rootPath = folderRoot.path
        if relative.hasPrefix(rootPath) {
            relative = String(relative.dropFirst(rootPath.count))
            while relative.hasPrefix("/") { relative = String(relative.dropFirst()) }
        } else {
            relative = source.lastPathComponent
        }
        if relative.isEmpty { relative = source.lastPathComponent }

        let dest = docs.appendingPathComponent(relative)
        try? FileManager.default.createDirectory(
            at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)

        if db.comicId(forFilePath: dest.path) != nil { return true }

        if !FileManager.default.fileExists(atPath: dest.path) {
            do {
                try FileManager.default.copyItem(at: source, to: dest)
            } catch {
                await MainActor.run { self.importError = error.localizedDescription }
                return false
            }
        }

        return await finalizeImport(dest: dest)
    }

    private func importCBR(_ source: URL, relativePathHint: String? = nil) async -> Bool {
        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Comics")
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)

        let folderName = relativePathHint ?? source.deletingPathExtension().lastPathComponent + ".cbr"
        let destDir    = docs.appendingPathComponent(folderName)

        if db.comicId(forFilePath: destDir.path) != nil { return true }

        let extractedURLs: [URL]
        do {
            extractedURLs = try await Task.detached(priority: .userInitiated) {
                try RARExtractor.extract(archiveURL: source, destination: destDir)
            }.value
        } catch {
            try? FileManager.default.removeItem(at: destDir)
            await MainActor.run { self.importError = error.localizedDescription }
            return false
        }

        let meta = ComicImporter.parse(url: source)
        db.insertComic(
            title:       meta.title,
            filePath:    destDir.path,
            publisher:   meta.publisher,
            character:   meta.character,
            series:      meta.series,
            issueNumber: meta.issueNumber,
            pageCount:   extractedURLs.count,
            writer:      meta.writer,
            summary:     meta.summary
        )
        return true
    }

    @discardableResult
    private func importFile(_ source: URL) async -> Bool {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        if source.pathExtension.lowercased() == "cbr" {
            return await importCBR(source)
        }

        let docs = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Comics")
        try? FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)

        let dest = docs.appendingPathComponent(source.lastPathComponent)

        if db.comicId(forFilePath: dest.path) != nil { return true }

        if !FileManager.default.fileExists(atPath: dest.path) {
            do {
                try FileManager.default.copyItem(at: source, to: dest)
            } catch {
                await MainActor.run { self.importError = error.localizedDescription }
                return false
            }
        }

        return await finalizeImport(dest: dest)
    }

    private func finalizeImport(dest: URL) async -> Bool {
        let meta      = ComicImporter.parse(url: dest)
        let pageCount = await ComicImporter.pageCount(url: dest)
        let ext       = dest.pathExtension.lowercased()
        if pageCount == 0 && (ext == "cbz" || ext == "pdf") {
            await MainActor.run {
                self.importError = "\(dest.lastPathComponent) appears to be empty or unreadable."
            }
            return false
        }
        db.insertComic(
            title:       meta.title,
            filePath:    dest.path,
            publisher:   meta.publisher,
            character:   meta.character,
            series:      meta.series,
            issueNumber: meta.issueNumber,
            pageCount:   pageCount,
            writer:      meta.writer,
            summary:     meta.summary
        )
        return true
    }

    // MARK: - Mutations

    func setRating(_ comic: Comic, rating: Int) {
        db.setRating(comic.id, rating)
        load()
    }

    func delete(_ comic: Comic) {
        _deleteOne(comic)
        load()
    }

    func deleteBatch(_ comics: [Comic]) {
        comics.forEach { _deleteOne($0) }
        load()
    }

    private func _deleteOne(_ comic: Comic) {
        let docsPath = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Comics").path
        if comic.filePath.hasPrefix(docsPath) {
            try? FileManager.default.removeItem(atPath: comic.filePath)
        }
        ThumbnailCache.shared.invalidate(comicId: comic.id)
        CBZReaderCache.shared.invalidate(path: comic.filePath)
        DirectoryReaderCache.shared.invalidate(path: comic.filePath)
        db.deleteComic(comic.id)
    }

    func updateProgress(_ comic: Comic, page: Int) {
        progressTask?.cancel()
        let comicId = comic.id
        let db = db
        progressTask = Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            db.updateProgress(comicId: comicId, page: page)
        }
    }
}
