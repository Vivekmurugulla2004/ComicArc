import SwiftUI

struct TagsView: View {
    @EnvironmentObject var library: LibraryViewModel
    @State private var tags: [Tag] = []
    @State private var renamingTag: Tag?
    @State private var mergingTag: Tag?
    @State private var newName: String = ""
    @State private var showRenameAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if tags.isEmpty {
                    ContentUnavailableView(
                        "No Tags",
                        systemImage: "tag",
                        description: Text("Add tags to comics from the comic detail page.")
                    )
                } else {
                    List {
                        ForEach(tags) { tag in
                            HStack {
                                Image(systemName: "tag.fill")
                                    .foregroundStyle(Color.arcGold)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tag.name).font(.subheadline)
                                    Text("\(tag.comicCount) comic\(tag.comicCount == 1 ? "" : "s")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) { deleteTag(tag) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button { startRename(tag) } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(Color.arcGold)
                                Button { mergingTag = tag } label: {
                                    Label("Merge", systemImage: "arrow.triangle.merge")
                                }
                                .tint(.blue)
                            }
                            .listRowBackground(Color.arcCard)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Color.arcBg)
            .navigationTitle("Tags")
            .onAppear { load() }
            .alert("Rename Tag", isPresented: $showRenameAlert, presenting: renamingTag) { tag in
                TextField("New name", text: $newName)
                Button("Rename") { performRename(tag) }
                Button("Cancel", role: .cancel) {}
            } message: { tag in
                Text("Rename \"\(tag.name)\"")
            }
            .sheet(item: $mergingTag) { tag in
                TagMergeSheet(sourceTag: tag, allTags: tags.filter { $0.id != tag.id }) { targetId in
                    Task.detached(priority: .utility) {
                        DatabaseManager.shared.mergeTag(sourceId: tag.id, intoId: targetId)
                        let updated = DatabaseManager.shared.allTagsWithCounts()
                        await MainActor.run { tags = updated }
                    }
                }
            }
        }
    }

    private func load() {
        Task.detached(priority: .utility) {
            let result = DatabaseManager.shared.allTagsWithCounts()
            await MainActor.run { tags = result }
        }
    }

    private func startRename(_ tag: Tag) {
        renamingTag = tag
        newName = tag.name
        showRenameAlert = true
    }

    private func performRename(_ tag: Tag) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task.detached(priority: .utility) {
            DatabaseManager.shared.renameTag(tag.id, to: trimmed)
            let updated = DatabaseManager.shared.allTagsWithCounts()
            await MainActor.run { tags = updated }
        }
    }

    private func deleteTag(_ tag: Tag) {
        Task.detached(priority: .utility) {
            DatabaseManager.shared.deleteTag(tag.id)
            let updated = DatabaseManager.shared.allTagsWithCounts()
            await MainActor.run { tags = updated }
        }
    }
}

private struct TagMergeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let sourceTag: Tag
    let allTags: [Tag]
    let onMerge: (Int64) -> Void
    @State private var selectedId: Int64?

    var body: some View {
        NavigationStack {
            List(allTags) { tag in
                HStack {
                    Image(systemName: selectedId == tag.id ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedId == tag.id ? Color.arcGold : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tag.name).font(.subheadline)
                        Text("\(tag.comicCount) comic\(tag.comicCount == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { selectedId = tag.id }
                .listRowBackground(Color.arcCard)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.arcBg)
            .navigationTitle("Merge \"\(sourceTag.name)\" into…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading)  { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Merge") {
                        if let id = selectedId { onMerge(id) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedId == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
