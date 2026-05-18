import SwiftUI

struct RunsView: View {
    @EnvironmentObject var library: LibraryViewModel
    @State private var runs: [Run] = []
    @State private var showCreate = false
    @State private var selectedRun: Run?

    var body: some View {
        NavigationStack {
            Group {
                if runs.isEmpty {
                    EmptyStateView(
                        icon: "list.number",
                        title: "No Reading Runs",
                        message: "Create a run to build an ordered reading path across multiple series and publishers."
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
                            let ids = offsets.map { runs[$0].id }
                            runs.remove(atOffsets: offsets)
                            Task {
                                await Task.detached(priority: .userInitiated) {
                                    ids.forEach { DatabaseManager.shared.deleteRun($0) }
                                }.value
                                load()
                            }
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
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                DatabaseManager.shared.allRuns()
            }.value
            runs = result
        }
    }
}

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
