import SwiftUI

struct RunsView: View {
    @EnvironmentObject var library: LibraryViewModel
    @State private var runs: [Run] = []
    @State private var showCreate = false
    @State private var selectedRun: Run?

    private let db = DatabaseManager.shared

    var body: some View {
        NavigationStack {
            Group {
                if runs.isEmpty {
                    ContentUnavailableView(
                        "No Reading Runs",
                        systemImage: "list.number",
                        description: Text("Create a run to build an ordered reading path across multiple series and publishers.")
                    )
                } else {
                    List {
                        ForEach(runs) { run in
                            Button { selectedRun = run } label: {
                                RunRow(run: run)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { offsets in
                            for i in offsets { db.deleteRun(runs[i].id) }
                            load()
                        }
                    }
                }
            }
            .navigationTitle("Reading Runs")
            .scrollContentBackground(.hidden)
            .background(Color.arcBg)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreate = true } label: {
                        Image(systemName: "plus")
                    }
                }
                if !runs.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                }
            }
            .sheet(isPresented: $showCreate, onDismiss: load) {
                CreateRunView()
            }
            .sheet(item: $selectedRun, onDismiss: load) { run in
                RunDetailView(run: run)
                    .environmentObject(library)
            }
            .onAppear { load() }
        }
    }

    private func load() {
        runs = db.allRuns()
    }
}

// MARK: - Run Row

struct RunRow: View {
    let run: Run

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(run.title)
                    .font(.headline)
                Spacer()
                if run.isFinished {
                    Label("Done", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(.green)
                } else if run.isStarted {
                    Label("Reading", systemImage: "book.fill")
                        .font(.caption).foregroundStyle(Color.arcGold)
                }
            }

            if !run.description.isEmpty {
                Text(run.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 12) {
                Label("\(run.itemCount) issue\(run.itemCount == 1 ? "" : "s")",
                      systemImage: "book")
                    .font(.caption2).foregroundStyle(.secondary)

                if run.itemCount > 0 {
                    ProgressView(value: run.progressPercent)
                        .tint(.arcGold)
                        .frame(maxWidth: 120)
                    Text("\(run.completedCount)/\(run.itemCount)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
