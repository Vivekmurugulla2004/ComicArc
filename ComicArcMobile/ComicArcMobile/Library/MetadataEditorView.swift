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
    @State private var tagsText: String    = ""   // comma-separated

    private let db = DatabaseManager.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Comic Info") {
                    LabeledField("Title", text: $title)
                    LabeledField("Publisher", text: $publisher)
                    LabeledField("Character", text: $character)
                    LabeledField("Series", text: $series)
                    LabeledField("Issue #", text: $issueNumber)
                        .keyboardType(.numberPad)
                }

                Section {
                    LabeledField("Tags", text: $tagsText)
                } footer: {
                    Text("Separate tags with commas: action, superhero, new 52")
                        .font(.caption)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.arcBg)
            .navigationTitle("Edit Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { load() }
        }
    }

    private func load() {
        let id = comicId
        Task {
            let (comic, tags) = await Task.detached(priority: .userInitiated) {
                (DatabaseManager.shared.comic(id: id), DatabaseManager.shared.tags(for: id))
            }.value
            guard let comic else { return }
            title       = comic.title
            publisher   = comic.publisher
            character   = comic.character ?? ""
            series      = comic.series
            issueNumber = comic.issueNumber ?? ""
            tagsText    = tags.map(\.name).joined(separator: ", ")
        }
    }

    private func save() {
        let ws      = CharacterSet.whitespaces
        let charVal = character.trimmingCharacters(in: ws)
        let serVal  = series.trimmingCharacters(in: ws)
        let numVal  = issueNumber.trimmingCharacters(in: ws)
        db.updateMetadata(
            comicId,
            title:       title.trimmingCharacters(in: ws),
            publisher:   publisher.trimmingCharacters(in: ws),
            character:   charVal.isEmpty ? nil      : charVal,
            series:      serVal.isEmpty  ? "General": serVal,
            issueNumber: numVal.isEmpty  ? nil      : numVal
        )

        let tagNames = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        db.setTags(for: comicId, names: tagNames)

        onSave()
        dismiss()
    }
}

// MARK: - Helper

private struct LabeledField: View {
    let label: String
    @Binding var text: String

    init(_ label: String, text: Binding<String>) {
        self.label = label
        self._text = text
    }

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            TextField(label, text: $text)
                .accessibilityLabel(label)
        }
    }
}
