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
        guard let comic = db.comic(id: comicId) else { return }
        title       = comic.title
        publisher   = comic.publisher
        character   = comic.character ?? ""
        series      = comic.series
        issueNumber = comic.issueNumber ?? ""

        let tags = db.tags(for: comicId)
        tagsText = tags.map(\.name).joined(separator: ", ")
    }

    private func save() {
        db.updateMetadata(
            comicId,
            title:       title.trimmingCharacters(in: .whitespaces),
            publisher:   publisher.trimmingCharacters(in: .whitespaces),
            character:   character.trimmingCharacters(in: .whitespaces).isEmpty
                         ? nil
                         : character.trimmingCharacters(in: .whitespaces),
            series:      series.trimmingCharacters(in: .whitespaces).isEmpty
                         ? "General"
                         : series.trimmingCharacters(in: .whitespaces),
            issueNumber: issueNumber.trimmingCharacters(in: .whitespaces).isEmpty
                         ? nil
                         : issueNumber.trimmingCharacters(in: .whitespaces)
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
        }
    }
}
