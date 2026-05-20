import SwiftUI

struct MetadataEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let comicId: Int64
    let onSave: () -> Void

    @State private var title: String       = ""
    @State private var publisher: String   = ""
    @State private var character: String   = ""
    @State private var series: String      = ""
    @State private var issueNumber: String = ""
    @State private var writer: String      = ""
    @State private var penciller: String   = ""
    @State private var yearText: String    = ""
    @State private var storyArc: String    = ""
    @State private var notes: String       = ""
    @State private var tagsText: String    = ""
    @State private var seriesDescription: String = ""

    @State private var showRenameSeriesSheet = false
    @State private var showMergeSeriesSheet  = false

    private let db = DatabaseManager.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Comic Info") {
                    LabeledField("Title",      text: $title)
                    LabeledField("Publisher",  text: $publisher)
                    LabeledField("Character",  text: $character)
                    LabeledField("Series",     text: $series)
                    LabeledField("Issue #",    text: $issueNumber).keyboardType(.numberPad)
                    LabeledField("Writer",     text: $writer)
                    LabeledField("Penciller",  text: $penciller)
                    LabeledField("Year",       text: $yearText).keyboardType(.numberPad)
                    LabeledField("Story Arc",  text: $storyArc)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }

                Section {
                    LabeledField("Tags", text: $tagsText)
                } footer: {
                    Text("Separate tags with commas: action, superhero, new 52")
                        .font(.caption)
                }

                let currentSeries = series.trimmingCharacters(in: .whitespaces)
                if !currentSeries.isEmpty && currentSeries != "General" {
                    Section("Series Description") {
                        TextEditor(text: $seriesDescription)
                            .frame(minHeight: 60)
                    }

                    Section("Series Actions") {
                        Button("Rename Series for All Comics") { showRenameSeriesSheet = true }
                        Button("Merge Another Series Into This One") { showMergeSeriesSheet = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.arcBg)
            .navigationTitle("Edit Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }.fontWeight(.semibold)
                }
            }
            .onAppear { load() }
            .sheet(isPresented: $showRenameSeriesSheet) {
                RenameSeriesSheet(
                    currentName: series.trimmingCharacters(in: .whitespaces),
                    publisher: publisher.trimmingCharacters(in: .whitespaces)
                ) { newName in series = newName; onSave() }
            }
            .sheet(isPresented: $showMergeSeriesSheet) {
                MergeSeriesSheet(
                    targetSeries: series.trimmingCharacters(in: .whitespaces),
                    publisher: publisher.trimmingCharacters(in: .whitespaces),
                    onMerged: onSave
                )
            }
        }
    }

    private func load() {
        let id = comicId
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (Comic?, [Tag], SeriesMeta?) in
                let comic = DatabaseManager.shared.comic(id: id)
                let tags  = DatabaseManager.shared.tags(for: id)
                let meta  = comic.flatMap {
                    DatabaseManager.shared.seriesMeta(publisher: $0.publisher, series: $0.series)
                }
                return (comic, tags, meta)
            }.value
            guard let comic = result.0 else { return }
            title             = comic.title
            publisher         = comic.publisher
            character         = comic.character ?? ""
            series            = comic.series
            issueNumber       = comic.issueNumber ?? ""
            writer            = comic.writer ?? ""
            penciller         = comic.penciller ?? ""
            yearText          = comic.year.map(String.init) ?? ""
            storyArc          = comic.storyArc ?? ""
            notes             = comic.notes ?? ""
            tagsText          = result.1.map(\.name).joined(separator: ", ")
            seriesDescription = result.2?.description ?? ""
        }
    }

    private func save() {
        let ws           = CharacterSet.whitespaces
        let titleVal     = title.trimmingCharacters(in: ws)
        let publisherVal = publisher.trimmingCharacters(in: ws)
        let charVal      = character.trimmingCharacters(in: ws)
        let serVal       = series.trimmingCharacters(in: ws)
        let numVal       = issueNumber.trimmingCharacters(in: ws)
        let writerVal    = writer.trimmingCharacters(in: ws)
        let pencillerVal = penciller.trimmingCharacters(in: ws)
        let storyArcVal  = storyArc.trimmingCharacters(in: ws)
        let notesVal     = notes.trimmingCharacters(in: ws)
        let serDescVal   = seriesDescription.trimmingCharacters(in: ws)
        let yearVal      = Int(yearText.trimmingCharacters(in: ws))
        let tagNames = tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let id = comicId
        Task {
            await Task.detached(priority: .userInitiated) {
                DatabaseManager.shared.updateMetadata(
                    id,
                    title:       titleVal,
                    publisher:   publisherVal,
                    character:   charVal.isEmpty      ? nil       : charVal,
                    series:      serVal.isEmpty        ? "General" : serVal,
                    issueNumber: numVal.isEmpty        ? nil       : numVal,
                    writer:      writerVal.isEmpty     ? nil       : writerVal,
                    penciller:   pencillerVal.isEmpty  ? nil       : pencillerVal,
                    year:        yearVal,
                    storyArc:    storyArcVal.isEmpty   ? nil       : storyArcVal,
                    notes:       notesVal.isEmpty      ? nil       : notesVal
                )
                DatabaseManager.shared.setTags(for: id, names: tagNames)
                if !serVal.isEmpty && serVal != "General" && !publisherVal.isEmpty {
                    DatabaseManager.shared.saveSeriesMeta(
                        publisher: publisherVal, series: serVal, description: serDescVal
                    )
                }
            }.value
            onSave()
            dismiss()
        }
    }
}

private struct RenameSeriesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let currentName: String
    let publisher: String
    let onRenamed: (String) -> Void
    @State private var newName: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("From").foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
                        Text(currentName).foregroundStyle(.primary)
                    }
                    HStack {
                        Text("To").foregroundStyle(.secondary).frame(width: 50, alignment: .leading)
                        TextField("New series name", text: $newName)
                    }
                } footer: {
                    Text("Renames this series for all \(publisher.isEmpty ? "comics" : "\(publisher) comics") in your library.")
                        .font(.caption)
                }
                if let error = errorMessage {
                    Section { Text(error).foregroundStyle(.red).font(.caption) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.arcBg)
            .navigationTitle("Rename Series")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Rename") { performRename() }
                        .fontWeight(.semibold)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
            .onAppear { newName = currentName }
        }
    }

    private func performRename() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != currentName else {
            errorMessage = "Enter a different name to rename."; return
        }
        isSaving = true
        let pub = publisher.isEmpty ? nil : publisher
        Task {
            await Task.detached(priority: .userInitiated) {
                DatabaseManager.shared.renameSeries(from: currentName, to: trimmed, publisher: pub)
            }.value
            onRenamed(trimmed)
            dismiss()
        }
    }
}

private struct MergeSeriesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let targetSeries: String
    let publisher: String
    let onMerged: () -> Void
    @State private var allSeries: [String] = []
    @State private var selected: Set<String> = []
    @State private var isMerging = false

    var body: some View {
        NavigationStack {
            Group {
                if allSeries.isEmpty {
                    ContentUnavailableView("No Other Series", systemImage: "square.stack",
                        description: Text("There are no other series to merge into \"\(targetSeries)\"."))
                } else {
                    List(allSeries, id: \.self, selection: $selected) { name in
                        HStack {
                            Image(systemName: selected.contains(name) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selected.contains(name) ? Color.arcGold : .secondary)
                            Text(name)
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selected.contains(name) { selected.remove(name) } else { selected.insert(name) }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color.arcBg)
            .navigationTitle("Merge Into \"\(targetSeries)\"")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Merge (\(selected.count))") { performMerge() }
                        .fontWeight(.semibold)
                        .disabled(selected.isEmpty || isMerging)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !selected.isEmpty {
                    VStack(alignment: .leading, spacing: .arcS4) {
                        Text("Merging \(selected.count) series into \"\(targetSeries)\"")
                            .font(.subheadline).fontWeight(.medium)
                        Text(selected.sorted().joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.arcS12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial)
                }
            }
            .onAppear { loadSeries() }
        }
    }

    private func loadSeries() {
        let pub = publisher.isEmpty ? nil : publisher
        let target = targetSeries
        Task {
            let result = await Task.detached(priority: .utility) {
                DatabaseManager.shared.allDistinctSeries(publisher: pub).filter { $0 != target }
            }.value
            allSeries = result
        }
    }

    private func performMerge() {
        guard !selected.isEmpty else { return }
        isMerging = true
        let sources = Array(selected)
        let target = targetSeries
        let pub = publisher.isEmpty ? nil : publisher
        Task {
            await Task.detached(priority: .userInitiated) {
                DatabaseManager.shared.mergeSeries(sources: sources, into: target, publisher: pub)
            }.value
            onMerged()
            dismiss()
        }
    }
}

private struct LabeledField: View {
    let label: String
    @Binding var text: String
    init(_ label: String, text: Binding<String>) { self.label = label; self._text = text }
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            TextField(label, text: $text).accessibilityLabel(label)
        }
    }
}
