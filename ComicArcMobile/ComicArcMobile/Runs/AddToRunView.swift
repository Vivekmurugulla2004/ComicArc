import SwiftUI

struct AddToRunView: View {
    @Environment(\.dismiss) private var dismiss

    let comicId: Int64
    @State private var runs: [Run] = []
    @State private var membership: Set<Int64> = []
    @State private var showCreate = false

    private let db = DatabaseManager.shared

    var body: some View {
        NavigationStack {
            List {
                if runs.isEmpty {
                    Text("No runs yet. Create one first.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(runs) { run in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(run.title).font(.subheadline)
                                Text("\(run.itemCount) issue\(run.itemCount == 1 ? "" : "s")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if membership.contains(run.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.arcGold)
                            } else {
                                Image(systemName: "circle")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { toggle(run: run) }
                    }
                }
            }
            .navigationTitle("Add to Run")
            .scrollContentBackground(.hidden)
            .background(Color.arcBg)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreate, onDismiss: load) {
                CreateRunView()
            }
            .onAppear { load() }
        }
    }

    private func load() {
        runs = db.allRuns()
        membership = Set(runs.filter { db.isComicInRun(runId: $0.id, comicId: comicId) }.map(\.id))
    }

    private func toggle(run: Run) {
        if membership.contains(run.id) {
            db.removeFromRun(runId: run.id, comicId: comicId)
            membership.remove(run.id)
        } else {
            db.addToRun(runId: run.id, comicId: comicId)
            membership.insert(run.id)
        }
    }
}
