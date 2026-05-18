import SwiftUI
import Combine

enum LibraryMutation {
    case setFavorite(id: Int64, value: Bool)
    case setInReadingList(id: Int64, value: Bool)
    case setRating(id: Int64, value: Int)
    case setProgress(id: Int64, page: Int)
    case setTags(id: Int64, tags: [String])
}

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

    @Published var importProgress = ImportProgress()
    @Published var importError: String?

    /// Set by ReaderView when user taps "Read Next" in a run — observed by RunDetailView
    @Published var pendingRunComic: Comic?

    private let db = DatabaseManager.shared
    private var importTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?

    // Last query params — used by reload() so delete/import can re-run with the same filter
    private var _lastPub: String?
    private var _lastTag: String?
    private var _lastSearch: String?
    private var _lastSort: DatabaseManager.SortOrder = .publisher

    #if DEBUG
    private var _isMutating = false
    #endif

    func apply(_ mutation: LibraryMutation) {
        #if DEBUG
        _isMutating = true
        defer { _isMutating = false }
        #endif
        let db = db
        switch mutation {
        case .setFavorite(let id, let value):
            Task.detached(priority: .utility) { db.setFavorite(id, value) }
            guard let idx = comics.firstIndex(where: { $0.id == id }) else { return }
            comics[idx].isFavorite = value

        case .setInReadingList(let id, let value):
            Task.detached(priority: .utility) { db.setInReadingList(id, value) }
            guard let idx = comics.firstIndex(where: { $0.id == id }) else { return }
            comics[idx].inReadingList = value

        case .setRating(let id, let value):
            Task.detached(priority: .utility) { db.setRating(id, value) }
            guard let idx = comics.firstIndex(where: { $0.id == id }) else { return }
            comics[idx].rating = value

        case .setProgress(let id, let page):
            Task.detached(priority: .utility) { db.updateProgress(comicId: id, page: page) }
            if let idx = comics.firstIndex(where: { $0.id == id }) {
                comics[idx].progress = page
            }
            // Derive inProgress in-memory: look up the comic from the filtered array
            // or from the existing inProgress list, then insert/remove as needed.
            let source = comics.first(where: { $0.id == id })
                      ?? inProgress.first(where: { $0.id == id })
            inProgress.removeAll { $0.id == id }
            if var c = source {
                c.progress = page
                if c.isStarted && !c.isFinished { inProgress.insert(c, at: 0) }
            }

        case .setTags(let id, let tags):
            Task.detached(priority: .utility) { db.setTags(for: id, names: tags) }
            guard let idx = comics.firstIndex(where: { $0.id == id }) else { return }
            comics[idx].tags = tags
        }
    }

    // MARK: - Batch Mutation

    func applyBatch(_ mutations: [LibraryMutation]) {
        guard !mutations.isEmpty else { return }
        #if DEBUG
        _isMutating = true
        defer { _isMutating = false }
        #endif

        var updated = comics  // local copy — no willSet until the final assignment below
        var favUpdates: [(id: Int64, value: Bool)] = []
        var listUpdates: [(id: Int64, value: Bool)] = []
        var progressUpdates: [(comicId: Int64, page: Int)] = []
        var needsProgressRefresh = false

        for mutation in mutations {
            switch mutation {
            case .setFavorite(let id, let value):
                if let idx = updated.firstIndex(where: { $0.id == id }) { updated[idx].isFavorite = value }
                favUpdates.append((id, value))
            case .setInReadingList(let id, let value):
                if let idx = updated.firstIndex(where: { $0.id == id }) { updated[idx].inReadingList = value }
                listUpdates.append((id, value))
            case .setRating(let id, let value):
                if let idx = updated.firstIndex(where: { $0.id == id }) { updated[idx].rating = value }
            case .setProgress(let id, let page):
                if let idx = updated.firstIndex(where: { $0.id == id }) { updated[idx].progress = page }
                progressUpdates.append((comicId: id, page: page))
                needsProgressRefresh = true
            }
        }

        comics = updated  // ONE @Published willSet → ONE objectWillChange.send()

        // Fire batched DB writes — grouped by type, one transaction per type
        let db = db
        if !favUpdates.isEmpty {
            // Partition by value in case a mixed-value batch ever occurs
            let trueIds  = favUpdates.filter(\.value).map(\.id)
            let falseIds = favUpdates.filter { !$0.value }.map(\.id)
            Task.detached(priority: .utility) {
                if !trueIds.isEmpty  { db.setFavoriteForIds(trueIds,  isFavorite: true) }
                if !falseIds.isEmpty { db.setFavoriteForIds(falseIds, isFavorite: false) }
            }
        }
        if !listUpdates.isEmpty {
            let trueIds  = listUpdates.filter(\.value).map(\.id)
            let falseIds = listUpdates.filter { !$0.value }.map(\.id)
            Task.detached(priority: .utility) {
                if !trueIds.isEmpty  { db.setInReadingListForIds(trueIds,  inList: true) }
                if !falseIds.isEmpty { db.setInReadingListForIds(falseIds, inList: false) }
            }
        }
        if !progressUpdates.isEmpty {
            Task.detached(priority: .utility) { db.updateProgressBatch(progressUpdates) }
        }

        if needsProgressRefresh {
            // Derive inProgress in-memory from the just-mutated comics copy.
            // Bulk progress mutations (e.g. mark-read) always operate on comics that
            // are in the current filtered view, so `updated` contains all affected structs.
            let affectedIds = Set(progressUpdates.map(\.comicId))
            inProgress.removeAll { affectedIds.contains($0.id) }
            for u in progressUpdates {
                if let c = updated.first(where: { $0.id == u.comicId }),
                   c.isStarted && !c.isFinished {
                    inProgress.insert(c, at: 0)
                }
            }
        }
    }

    // MARK: - Load

    func load(publisher: String? = nil, tag: String? = nil,
              search: String? = nil, sortOrder: DatabaseManager.SortOrder = .publisher) {
        #if DEBUG
        assert(!_isMutating, "load() called from within apply/applyBatch — use apply/applyBatch for UI mutations")
        #endif
        _lastPub = publisher; _lastTag = tag; _lastSearch = search; _lastSort = sortOrder
        let db = db
        Task.detached(priority: .userInitiated) { [weak self] in
            let publishers      = db.publishers()
            let inProgress      = db.inProgress()
            let allTags         = db.allTags()
            let characterGroups = db.characterGroups(publisher: publisher)
            let comics: [Comic] = tag != nil
                ? db.comics(withTag: tag!)
                : db.allComics(publisher: publisher, search: search, sortOrder: sortOrder)
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

    // Re-runs the last load() call with the same filter params.
    // Used internally by delete/import so filters survive structural changes.
    private func reload() {
        load(publisher: _lastPub, tag: _lastTag, search: _lastSearch, sortOrder: _lastSort)
    }

    // Call after an external write (e.g. MetadataEditorView) that changes fields
    // not covered by LibraryMutation — triggers a full structural reload.
    func reloadAfterExternalWrite() {
        reload()
    }

    func loadSeries(for character: String, publisher: String? = nil) {
        let db = db
        Task.detached(priority: .userInitiated) { [weak self] in
            let groups = db.seriesGroups(character: character, publisher: publisher)
            guard let self else { return }
            await MainActor.run { self.seriesGroups = groups }
        }
    }

    func loadIssues(character: String?, series: String,
                    publisher: String? = nil, sortOrder: DatabaseManager.SortOrder = .publisher) {
        let db = db
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = db.allComics(
                publisher: publisher, character: character, series: series,
                nullCharacterOnly: character == nil, sortOrder: sortOrder
            )
            guard let self else { return }
            await MainActor.run { self.comics = result }
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
                self.reload()
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
                self.reload()
            }
        }
    }

    // MARK: - Private import helpers (nonisolated static — run off main thread)

    private nonisolated static var comicsDir: URL {
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

    func delete(_ comic: Comic) {
        let filePath = comic.filePath
        let comicId  = comic.id
        // Caches + DB: fast, synchronous — comic disappears from UI immediately.
        ThumbnailCache.shared.invalidate(comicId: comicId)
        CBZReaderCache.shared.invalidate(path: filePath)
        DirectoryReaderCache.shared.invalidate(path: filePath)
        db.deleteComic(comicId)
        reload()
        // File removal: potentially slow (100MB+ files) — never block the main thread.
        removeFileIfOwned(filePath)
    }

    func deleteBatch(_ comics: [Comic]) {
        let docsPath = Self.comicsDir.path
        let paths = comics.map(\.filePath)
        comics.forEach { comic in
            ThumbnailCache.shared.invalidate(comicId: comic.id)
            CBZReaderCache.shared.invalidate(path: comic.filePath)
            DirectoryReaderCache.shared.invalidate(path: comic.filePath)
            db.deleteComic(comic.id)
        }
        reload()
        Task.detached(priority: .background) {
            for path in paths where path.hasPrefix(docsPath) {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
    }

    private func removeFileIfOwned(_ filePath: String) {
        let docsPath = Self.comicsDir.path
        guard filePath.hasPrefix(docsPath) else { return }
        Task.detached(priority: .background) {
            try? FileManager.default.removeItem(atPath: filePath)
        }
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
