import SwiftUI

struct RunDetailView: View {
    @EnvironmentObject var library: LibraryViewModel
    @Environment(\.dismiss) private var dismiss

    let run: Run
    @State private var items: [RunItem] = []
    @State private var showEdit = false
    @State private var readerComic: Comic?
    @State private var readerRunContext: [Comic] = []
    @State private var detailComicId: Int64?
    @State private var missingFileComic: Comic?

    private func openComic(_ comic: Comic, context: [Comic]) {
        if FileManager.default.fileExists(atPath: comic.filePath) {
            readerRunContext = context
            readerComic = comic
        } else {
            missingFileComic = comic
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    EmptyStateView(
                        icon: "book",
                        title: "No Comics Yet",
                        message: "Open a comic's detail page and tap \"Add to Run\" to add it here."
                    )
                } else {
                    List {
                        // Resume banner
                        if let firstUnfinished = items.first(where: { !$0.isFinished }) {
                            Section {
                                Button {
                                    openComic(firstUnfinished.comic, context: items.map(\.comic))
                                } label: {
                                    HStack {
                                        Image(systemName: "play.fill")
                                            .foregroundStyle(.white)
                                            .frame(width: 36, height: 36)
                                            .background(Color.arcGold)
                                            .clipShape(Circle())
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Resume Run")
                                                .font(.headline)
                                            Text(firstUnfinished.comic.title)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Issues list
                        Section {
                            ForEach(items) { item in
                                RunItemRow(item: item,
                                           allComics: items.map(\.comic),
                                           onRead: { comic, context in
                                               openComic(comic, context: context)
                                           },
                                           onDetail: { detailComicId = item.comic.id },
                                           onNotesChanged: { notes in
                                               let itemId = item.id
                                               Task {
                                                   await Task.detached(priority: .utility) {
                                                       DatabaseManager.shared.updateRunItemNotes(itemId: itemId, notes: notes)
                                                   }.value
                                               }
                                           })
                            }
                            .onMove { from, to in
                                var reordered = items
                                reordered.move(fromOffsets: from, toOffset: to)
                                items = reordered
                                let runId = run.id
                                let orderedIds = reordered.map(\.id)
                                Task {
                                    await Task.detached(priority: .userInitiated) {
                                        DatabaseManager.shared.reorderRunItems(runId: runId, orderedItemIds: orderedIds)
                                    }.value
                                }
                            }
                            .onDelete { offsets in
                                let runId = run.id
                                let comicIds = offsets.map { items[$0].comic.id }
                                load()
                                Task {
                                    await Task.detached(priority: .userInitiated) {
                                        for cid in comicIds {
                                            DatabaseManager.shared.removeFromRun(runId: runId, comicId: cid)
                                        }
                                    }.value
                                }
                            }
                        }
                    }
                    .environment(\.editMode, .constant(.active))
                }
            }
            .navigationTitle(run.title)
            .scrollContentBackground(.hidden)
            .background(Color.arcBg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showEdit = true } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
            .sheet(isPresented: $showEdit) {
                CreateRunView(existingRun: run)
            }
            .sheet(item: $readerComic) { comic in
                ReaderView(comic: comic, runQueue: readerRunContext)
                    .environmentObject(library)
                    .onDisappear {
                        load()
                        // Pick up auto-advance request set by ReaderView "Read Next" banner
                        if let pending = library.pendingRunComic {
                            library.pendingRunComic = nil
                            readerRunContext = items.map(\.comic)
                            readerComic = pending
                        }
                    }
            }
            .sheet(item: Binding(
                get: { detailComicId.map { ComicSheetID(id: $0) } },
                set: { detailComicId = $0?.id }
            )) { wrapper in
                ComicDetailView(comicId: wrapper.id)
                    .environmentObject(library)
                    .onDisappear { load() }
            }
            .onAppear { load() }
            .alert("File Not Found", isPresented: Binding(
                get: { missingFileComic != nil },
                set: { if !$0 { missingFileComic = nil } }
            )) {
                Button("Remove from Library", role: .destructive) {
                    if let c = missingFileComic {
                        library.delete(c)
                        load()
                    }
                    missingFileComic = nil
                }
                Button("Cancel", role: .cancel) { missingFileComic = nil }
            } message: {
                Text("The file for \"\(missingFileComic?.title ?? "this comic")\" can't be found on your device.")
            }
        }
    }

    private func load() {
        let runId = run.id
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                DatabaseManager.shared.runItems(runId: runId)
            }.value
            items = result
        }
    }
}

// MARK: - Run Item Row

struct RunItemRow: View {
    let item: RunItem
    let allComics: [Comic]
    let onRead: (Comic, [Comic]) -> Void
    let onDetail: () -> Void
    let onNotesChanged: (String) -> Void

    @State private var notes: String = ""
    @State private var showNotes = false

    var body: some View {
        HStack(spacing: 12) {
            // Position indicator / status
            ZStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 28, height: 28)
                if item.isFinished {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                } else {
                    Text("\(item.position + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
            }

            // Cover thumbnail
            CoverImage(comicId: item.comic.id)
                .frame(width: 36, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(item.comic.title)
                    .font(.subheadline)
                    .lineLimit(2)
                Text(item.comic.series)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !item.notes.isEmpty {
                    Text(item.notes)
                        .font(.caption2)
                        .foregroundStyle(Color.arcGold)
                        .lineLimit(1)
                }
                if item.comic.pageCount > 0 && item.comic.isStarted && !item.isFinished {
                    ProgressView(value: item.comic.progressPercent)
                        .tint(.arcGold)
                        .frame(maxWidth: 120)
                }
            }

            Spacer()

            // Actions
            Menu {
                Button {
                    onRead(item.comic, allComics)
                } label: {
                    Label(item.comic.isStarted ? "Continue" : "Read",
                          systemImage: "book")
                }
                Button { onDetail() } label: {
                    Label("View Details", systemImage: "info.circle")
                }
                Button {
                    notes = item.notes
                    showNotes = true
                } label: {
                    Label("Edit Notes", systemImage: "note.text")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("Comic options")
            }
        }
        .padding(.vertical, 2)
        .alert("Notes", isPresented: $showNotes) {
            TextField("Add a note…", text: $notes)
            Button("Save") { onNotesChanged(notes) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var statusColor: Color {
        if item.isFinished { return .green }
        if item.isStarted  { return .arcGold }
        return Color.arcMuted
    }
}


