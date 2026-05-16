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
        let db = db
        importTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            try? FileManager.default.createDirectory(at: Self.comicsDir, withIntermediateDirectories: true)

            var done = 0
            var failures = 0

            await withTaskGroup(of: (Bool, String).self) { group in
                var remaining = urls
                var inFlight  = 0
                let limit     = 4

                while !remaining.isEmpty && inFlight < limit {
                    let url  = remaining.removeFirst()
                    let name = url.lastPathComponent
                    group.addTask { (await Self.importOne(source: url, db: db), name) }
                    inFlight += 1
                }

                while let (ok, name) = await group.next() {
                    inFlight -= 1
                    if !ok { failures += 1 }
                    done += 1
                    let d = done, f = failures, n = name
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.importProgress.done        = d
                        self.importProgress.failures    = f
                        self.importProgress.currentFile = n
                    }
                    if !remaining.isEmpty {
                        let url  = remaining.removeFirst()
                        let name = url.lastPathComponent
                        group.addTask { (await Self.importOne(source: url, db: db), name) }
                        inFlight += 1
                    }
                }
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.importProgress = ImportProgress()
                self.load()
            }
        }
    }

    func importFolder(_ folderURL: URL) {
        importTask?.cancel()
        importProgress = ImportProgress(isScanning: true)
        let db = db
        importTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            let accessing = folderURL.startAccessingSecurityScopedResource()
            guard accessing else {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.importProgress = ImportProgress()
                    self.importError = "Could not access the selected folder."
                }
                return
            }
            defer { folderURL.stopAccessingSecurityScopedResource() }

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
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.importProgress = ImportProgress(done: 0, total: fileCount, currentFile: "", failures: 0)
            }

            try? FileManager.default.createDirectory(at: Self.comicsDir, withIntermediateDirectories: true)

            var done = 0
            var failures = 0

            await withTaskGroup(of: (Bool, String).self) { group in
                var remaining = files
                var inFlight  = 0
                let limit     = 4

                while !remaining.isEmpty && inFlight < limit {
                    let fileURL = remaining.removeFirst()
                    let name    = fileURL.lastPathComponent
                    group.addTask { (await Self.importFromFolder(fileURL, folderRoot: folderURL, db: db), name) }
                    inFlight += 1
                }

                while let (ok, name) = await group.next() {
                    inFlight -= 1
                    if !ok { failures += 1 }
                    done += 1
                    let d = done, f = failures, n = name
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.importProgress.done        = d
                        self.importProgress.failures    = f
                        self.importProgress.currentFile = n
                    }
                    if !remaining.isEmpty {
                        let fileURL = remaining.removeFirst()
                        let name    = fileURL.lastPathComponent
                        group.addTask { (await Self.importFromFolder(fileURL, folderRoot: folderURL, db: db), name) }
                        inFlight += 1
                    }
                }
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.importProgress = ImportProgress()
                self.load()
            }
        }
    }

    // MARK: - Private import helpers (nonisolated static — run off main thread)

    private static var comicsDir: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Comics")
    }

    private static func importOne(source: URL, db: DatabaseManager) async -> Bool {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        if source.pathExtension.lowercased() == "cbr" {
            let destDir = comicsDir.appendingPathComponent(
                source.deletingPathExtension().lastPathComponent + ".cbr"
            )
            return importCBR(source: source, destDir: destDir, db: db)
        }

        let dest = comicsDir.appendingPathComponent(source.lastPathComponent)
        return await copyThenFinalize(source: source, dest: dest, db: db)
    }

    private static func importFromFolder(_ source: URL, folderRoot: URL, db: DatabaseManager) async -> Bool {
        var rel = source.path
        let rootPath = folderRoot.path
        if rel.hasPrefix(rootPath) {
            rel = String(rel.dropFirst(rootPath.count))
            while rel.hasPrefix("/") { rel = String(rel.dropFirst()) }
        } else {
            rel = source.lastPathComponent
        }
        if rel.isEmpty { rel = source.lastPathComponent }

        if source.pathExtension.lowercased() == "cbr" {
            let cbrFolder = URL(fileURLWithPath: rel).deletingPathExtension().path + ".cbr"
            let destDir   = comicsDir.appendingPathComponent(cbrFolder)
            return importCBR(source: source, destDir: destDir, db: db)
        }

        let dest = comicsDir.appendingPathComponent(rel)
        try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        return await copyThenFinalize(source: source, dest: dest, db: db)
    }

    private static func importCBR(source: URL, destDir: URL, db: DatabaseManager) -> Bool {
        if db.comicId(forFilePath: destDir.path) != nil { return true }

        let extracted: [URL]
        do {
            extracted = try RARExtractor.extract(archiveURL: source, destination: destDir)
        } catch {
            try? FileManager.default.removeItem(at: destDir)
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
            pageCount:   extracted.count,
            writer:      meta.writer,
            summary:     meta.summary
        )
        return true
    }

    private static func copyThenFinalize(source: URL, dest: URL, db: DatabaseManager) async -> Bool {
        if db.comicId(forFilePath: dest.path) != nil { return true }

        if !FileManager.default.fileExists(atPath: dest.path) {
            do {
                try FileManager.default.copyItem(at: source, to: dest)
            } catch {
                return false
            }
        }

        return await finalize(dest: dest, db: db)
    }

    private static func finalize(dest: URL, db: DatabaseManager) async -> Bool {
        let meta      = ComicImporter.parse(url: dest)
        let pageCount = await ComicImporter.pageCount(url: dest)
        let ext       = dest.pathExtension.lowercased()
        if pageCount == 0 && (ext == "cbz" || ext == "pdf") { return false }
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
