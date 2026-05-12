import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var library: LibraryViewModel
    @AppStorage("defaultReadMode") private var defaultReadMode: String = "paged"
    @State private var showClearConfirm = false
    @State private var showExportSheet = false
    @State private var exportURL: URL?

    private let db = DatabaseManager.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Reader") {
                    Picker("Default Mode", selection: $defaultReadMode) {
                        Text("Page by Page").tag("paged")
                        Text("Vertical Scroll").tag("scroll")
                    }
                }

                Section("Library") {
                    Button("Export Backup (JSON)") { exportBackup() }
                    Button("Clear Library", role: .destructive) { showClearConfirm = true }
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Platform", value: "iOS")
                    Link("GitHub", destination: URL(string: "https://github.com/ComicArc/ComicArc")!)
                }
            }
            .navigationTitle("Settings")
            .confirmationDialog(
                "Clear all library data? Your files will not be deleted.",
                isPresented: $showClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear Library", role: .destructive) {
                    clearLibrary()
                }
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
        var entries: [[String: Any]] = []
        for c in comics {
            entries.append([
                "id": c.id,
                "title": c.title,
                "publisher": c.publisher,
                "character": c.character ?? "",
                "series": c.series,
                "issue_number": c.issueNumber ?? "",
                "page_count": c.pageCount,
                "progress": c.progress,
                "rating": c.rating,
                "is_favorite": c.isFavorite,
                "in_reading_list": c.inReadingList,
                "tags": c.tags
            ])
        }
        guard let data = try? JSONSerialization.data(withJSONObject: entries, options: .prettyPrinted) else { return }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ComicArc-backup.json")
        try? data.write(to: url)
        exportURL = url
        showExportSheet = true
    }

    private func clearLibrary() {
        // Delete all comics (cascades to reading_progress via FK)
        for comic in db.allComics() { db.deleteComic(comic.id) }
        // Wipe cover cache
        let coversDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ComicArc/covers")
        try? FileManager.default.removeItem(at: coversDir)
        library.load()
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
