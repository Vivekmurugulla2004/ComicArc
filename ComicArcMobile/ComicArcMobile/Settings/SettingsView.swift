import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var library: LibraryViewModel
    @AppStorage("defaultReadMode") private var defaultReadMode: String = "paged"
    @AppStorage("onboardingDone") private var onboardingDone = true
    @AppStorage("autoplayInterval") private var autoplayInterval: Double = 10
    @State private var showClearConfirm = false
    @State private var showExportSheet = false
    @State private var showImportBackup = false
    @State private var exportURL: URL?
    @State private var storageSize: String = "…"
    @State private var restoreResult: String?
    @State private var isRestoring = false

    private let db = DatabaseManager.shared
    private let comicsFolder = FileManager.default
        .urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Comics").path

    var body: some View {
        NavigationStack {
            List {
                Section("Reader") {
                    Picker("Default Mode", selection: $defaultReadMode) {
                        Text("Page by Page").tag("paged")
                        Text("Vertical Scroll").tag("scroll")
                    }
                    .accessibilityLabel("Default reading mode")

                    HStack {
                        Text("Autoplay Interval")
                        Spacer()
                        Stepper("\(Int(autoplayInterval))s",
                                value: $autoplayInterval,
                                in: 3...30, step: 1)
                        .accessibilityLabel("Autoplay interval, \(Int(autoplayInterval)) seconds")
                    }
                }

                Section("Library") {
                    NavigationLink {
                        StatsView().environmentObject(library)
                    } label: {
                        Label("Library Stats", systemImage: "chart.bar")
                    }
                    .accessibilityLabel("View library stats")

                    LabeledContent("Comics", value: "\(db.scalarInt("SELECT COUNT(*) FROM comics"))")
                    LabeledContent("Storage Used", value: storageSize)

                    Button("Export Backup (JSON)") { exportBackup() }
                        .accessibilityLabel("Export library backup as JSON")

                    Button {
                        showImportBackup = true
                    } label: {
                        if isRestoring {
                            HStack { ProgressView(); Text("Restoring…") }
                        } else {
                            Text("Import Backup (JSON)")
                        }
                    }
                    .disabled(isRestoring)
                    .accessibilityLabel("Import library backup from JSON")
                }

                Section {
                    Button("Replay Onboarding") { onboardingDone = false }
                        .foregroundStyle(Color.arcGold)
                        .accessibilityLabel("Replay onboarding")
                    Button("Clear Library", role: .destructive) { showClearConfirm = true }
                        .accessibilityLabel("Clear library")
                        .accessibilityHint("Removes all comics and deletes files from the Comics folder")
                } footer: {
                    Text("Clear Library removes all comics. Files in your Comics folder are also deleted.")
                }

                Section("Supported Formats") {
                    LabeledContent("CBZ", value: "Supported")
                    LabeledContent("PDF", value: "Supported")
                    LabeledContent("JPEG / PNG", value: "Supported")
                    LabeledContent("CBR", value: "Not supported")
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Platform", value: "iOS \(UIDevice.current.systemVersion)")
                }
            }
            .navigationTitle("Settings")
            .scrollContentBackground(.hidden)
            .background(Color.arcBg)
            .onAppear { computeStorageSize() }
            .confirmationDialog(
                "Clear all library data? Comics in your Documents folder will also be deleted.",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear Library", role: .destructive) { clearLibrary() }
            }
            .sheet(isPresented: $showExportSheet) {
                if let url = exportURL {
                    ShareSheet(url: url)
                }
            }
            .fileImporter(
                isPresented: $showImportBackup,
                allowedContentTypes: [.json]
            ) { result in
                if case .success(let url) = result { restoreBackup(from: url) }
            }
            .alert("Restore Complete", isPresented: Binding(
                get: { restoreResult != nil },
                set: { if !$0 { restoreResult = nil } }
            )) {
                Button("OK", role: .cancel) { restoreResult = nil }
            } message: {
                Text(restoreResult ?? "")
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    // MARK: - Export

    private func exportBackup() {
        let comics = db.allComics()
        let runs   = db.allRuns()

        let comicEntries: [[String: Any]] = comics.map { c in
            // Store path relative to Comics folder so it's device-independent
            var relPath = c.filePath
            if relPath.hasPrefix(comicsFolder) {
                relPath = String(relPath.dropFirst(comicsFolder.count))
                while relPath.hasPrefix("/") { relPath = String(relPath.dropFirst()) }
            }
            return [
                "id": c.id,
                "title": c.title,
                "file_path": relPath,
                "publisher": c.publisher,
                "character": c.character ?? "",
                "series": c.series,
                "issue_number": c.issueNumber ?? "",
                "page_count": c.pageCount,
                "progress": c.progress,
                "rating": c.rating,
                "is_favorite": c.isFavorite,
                "in_reading_list": c.inReadingList,
                "tags": db.tags(for: c.id).map(\.name)
            ]
        }

        let runEntries: [[String: Any]] = runs.map { r in
            let items = db.runItems(runId: r.id).map { item in [
                "comic_id": item.comic.id,
                "title": item.comic.title,
                "position": item.position,
                "notes": item.notes
            ] as [String: Any] }
            return ["id": r.id, "title": r.title,
                    "description": r.description, "items": items] as [String: Any]
        }

        let payload: [String: Any] = [
            "exported_at": ISO8601DateFormatter().string(from: Date()),
            "app": "ComicArc iOS",
            "version": 2,
            "comics": comicEntries,
            "runs": runEntries
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: .prettyPrinted) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ComicArc-backup.json")
        try? data.write(to: url)
        exportURL = url
        showExportSheet = true
    }

    // MARK: - Restore

    private func restoreBackup(from url: URL) {
        isRestoring = true
        Task.detached { [db, comicsFolder] in
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let comicList = json["comics"] as? [[String: Any]] else {
                await MainActor.run { isRestoring = false; restoreResult = "Invalid backup file." }
                return
            }

            var restoredComics = 0
            var idMap: [Int64: Int64] = [:]  // backup ID → current DB ID

            for c in comicList {
                let relPath   = c["file_path"]    as? String ?? ""
                let title     = c["title"]        as? String ?? ""
                let publisher = c["publisher"]    as? String ?? "Unknown"
                let character = (c["character"]   as? String).flatMap { $0.isEmpty ? nil : $0 }
                let series    = c["series"]       as? String ?? "General"
                let issueNum  = (c["issue_number"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let pageCount = c["page_count"]   as? Int ?? 0
                let progress  = c["progress"]     as? Int ?? 0
                let rating    = c["rating"]       as? Int ?? 0
                let isFav     = c["is_favorite"]  as? Bool ?? false
                let inRL      = c["in_reading_list"] as? Bool ?? false
                let tags      = c["tags"]         as? [String] ?? []
                let backupId  = (c["id"]          as? Int).map { Int64($0) } ?? 0

                guard !relPath.isEmpty else { continue }
                let fullPath = (comicsFolder as NSString).appendingPathComponent(relPath)

                guard let newId = db.restoreComic(
                    title: title, filePath: fullPath,
                    publisher: publisher, character: character,
                    series: series, issueNumber: issueNum,
                    pageCount: pageCount, rating: rating,
                    isFavorite: isFav, inReadingList: inRL
                ) else { continue }

                if backupId > 0 { idMap[backupId] = newId }
                if progress > 0 { db.updateProgress(comicId: newId, page: progress) }
                if !tags.isEmpty { db.setTags(for: newId, names: tags) }
                restoredComics += 1
            }

            // Restore runs, mapping backup comic IDs to current IDs
            var restoredRuns = 0
            if let runList = json["runs"] as? [[String: Any]] {
                for r in runList {
                    guard let title = r["title"] as? String, !title.isEmpty else { continue }
                    let desc  = r["description"] as? String ?? ""
                    let items = (r["items"] as? [[String: Any]] ?? [])
                        .sorted { ($0["position"] as? Int ?? 0) < ($1["position"] as? Int ?? 0) }
                    guard let runId = db.createRun(title: title, description: desc) else { continue }
                    for item in items {
                        let oldId = (item["comic_id"] as? Int).map { Int64($0) } ?? 0
                        if let currentId = idMap[oldId] {
                            db.addToRun(runId: runId, comicId: currentId)
                        }
                    }
                    restoredRuns += 1
                }
            }

            let msg = "Restored \(restoredComics) comic\(restoredComics == 1 ? "" : "s")" +
                      " and \(restoredRuns) run\(restoredRuns == 1 ? "" : "s")."
            await MainActor.run {
                isRestoring = false
                library.load()
                restoreResult = msg
            }
        }
    }

    // MARK: - Clear

    private func clearLibrary() {
        let comicsDir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Comics")
        try? FileManager.default.removeItem(at: comicsDir)

        for comic in db.allComics() { db.deleteComic(comic.id) }
        for run in db.allRuns()     { db.deleteRun(run.id) }

        let coversDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ComicArc/covers")
        try? FileManager.default.removeItem(at: coversDir)

        ThumbnailCache.shared.invalidateAll()
        PageImageCache.shared.invalidate()
        CBZReaderCache.shared.invalidateAll()

        library.load()
    }

    // MARK: - Storage

    private func computeStorageSize() {
        Task.detached {
            let comicsDir = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Comics")
            let bytes = directorySize(url: comicsDir)
            let formatted = ByteCountFormatter.string(
                fromByteCount: Int64(bytes), countStyle: .file)
            await MainActor.run { storageSize = formatted }
        }
    }

    private nonisolated func directorySize(url: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total = 0
        for case let fileURL as URL in enumerator {
            total += (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
