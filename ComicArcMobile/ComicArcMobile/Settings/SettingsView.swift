import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var library: LibraryViewModel
    @AppStorage("defaultReadMode") private var defaultReadMode: String = "paged"
    @AppStorage("autoplayInterval") private var autoplayInterval: Double = 10
    @State private var showClearConfirm = false
    @State private var showExportSheet = false
    @State private var exportURL: URL?
    @State private var storageSize: String = "…"

    private let db = DatabaseManager.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Reader") {
                    Picker("Default Mode", selection: $defaultReadMode) {
                        Text("Page by Page").tag("paged")
                        Text("Vertical Scroll").tag("scroll")
                    }

                    HStack {
                        Text("Autoplay Interval")
                        Spacer()
                        Stepper("\(Int(autoplayInterval))s",
                                value: $autoplayInterval,
                                in: 3...30, step: 1)
                    }
                }

                Section("Library") {
                    LabeledContent("Comics", value: "\(db.scalarInt("SELECT COUNT(*) FROM comics"))")
                    LabeledContent("Storage Used", value: storageSize)

                    Button("Export Backup (JSON)") { exportBackup() }
                }

                Section {
                    Button("Clear Library", role: .destructive) { showClearConfirm = true }
                } footer: {
                    Text("Removes all comics from the library. Your files in the Comics folder are also deleted.")
                }

                Section("Formats") {
                    LabeledContent("CBZ", value: "Built-in")
                    LabeledContent("PDF", value: "Built-in")
                    LabeledContent("CBR", value: "Not supported on iOS")
                    LabeledContent("JPEG / PNG", value: "Built-in")
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Platform", value: "iOS \(UIDevice.current.systemVersion)")
                    Link("GitHub",
                         destination: URL(string: "https://github.com/ComicArc/ComicArc")!)
                    Link("Report an Issue",
                         destination: URL(string: "https://github.com/ComicArc/ComicArc/issues")!)
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
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private func exportBackup() {
        let comics = db.allComics()
        let runs   = db.allRuns()

        let comicEntries: [[String: Any]] = comics.map { c in [
            "id": c.id, "title": c.title, "publisher": c.publisher,
            "character": c.character ?? "", "series": c.series,
            "issue_number": c.issueNumber ?? "", "page_count": c.pageCount,
            "progress": c.progress, "rating": c.rating,
            "is_favorite": c.isFavorite, "in_reading_list": c.inReadingList,
            "tags": db.tags(for: c.id).map(\.name)
        ]}

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

        library.load()
    }

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
