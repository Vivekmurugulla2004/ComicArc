import SwiftUI

struct TrashView: View {
    @EnvironmentObject var library: LibraryViewModel
    @State private var trashed: [Comic] = []
    @State private var showPurgeAllConfirm = false

    var body: some View {
        NavigationStack {
            Group {
                if trashed.isEmpty {
                    ContentUnavailableView(
                        "Trash is Empty",
                        systemImage: "trash",
                        description: Text("Deleted comics appear here for 30 days before being permanently removed.")
                    )
                } else {
                    List {
                        ForEach(trashed) { comic in
                            HStack(spacing: 12) {
                                CoverImage(comic: comic)
                                    .frame(width: 44, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(comic.title)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                    Text("\(comic.publisher) · \(comic.series)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    if comic.pageCount > 0 {
                                        Text("\(comic.pageCount) pages")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                VStack(spacing: 6) {
                                    Button("Restore") { restore(comic) }
                                        .font(.caption.bold())
                                        .foregroundStyle(Color.arcGold)
                                    Button("Delete") { purge(comic) }
                                        .font(.caption)
                                        .foregroundStyle(Color.arcRed)
                                }
                            }
                            .listRowBackground(Color.arcCard)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.arcBg)
            .navigationTitle("Trash")
            .toolbar {
                if !trashed.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Empty Trash") { showPurgeAllConfirm = true }
                            .foregroundStyle(Color.arcRed)
                    }
                }
            }
            .confirmationDialog(
                "Permanently delete all \(trashed.count) comic\(trashed.count == 1 ? "" : "s")? This cannot be undone.",
                isPresented: $showPurgeAllConfirm,
                titleVisibility: .visible
            ) {
                Button("Empty Trash", role: .destructive) { purgeAll() }
            }
            .onAppear { load() }
        }
    }

    private func load() {
        Task.detached(priority: .utility) {
            DatabaseManager.shared.purgeExpiredTrash()
            let items = DatabaseManager.shared.trashedComics()
            await MainActor.run { trashed = items }
        }
    }

    private func restore(_ comic: Comic) {
        DatabaseManager.shared.restoreComic(fromTrash: comic.id)
        trashed.removeAll { $0.id == comic.id }
        library.reloadAfterExternalWrite()
    }

    private func purge(_ comic: Comic) {
        library.purgeComic(comic)
        trashed.removeAll { $0.id == comic.id }
    }

    private func purgeAll() {
        for comic in trashed { library.purgeComic(comic) }
        trashed.removeAll()
    }
}
