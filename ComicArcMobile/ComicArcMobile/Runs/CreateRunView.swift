import SwiftUI

struct CreateRunView: View {
    @Environment(\.dismiss) private var dismiss

    var existingRun: Run? = nil

    @State private var title: String = ""
    @State private var description: String = ""

    private let db = DatabaseManager.shared
    private var isEditing: Bool { existingRun != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Run Details") {
                    TextField("Title", text: $title)
                    TextField("Description (optional)", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.arcBg)
            .navigationTitle(isEditing ? "Edit Run" : "New Run")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(isEditing ? "Save" : "Create") {
                        if isEditing, let run = existingRun {
                            db.updateRun(run.id, title: title, description: description)
                        } else {
                            db.createRun(title: title, description: description)
                        }
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let run = existingRun {
                    title       = run.title
                    description = run.description
                }
            }
        }
    }
}
