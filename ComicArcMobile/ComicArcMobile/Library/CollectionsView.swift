import SwiftUI

struct CollectionsView: View {
    @EnvironmentObject var library: LibraryViewModel
    @State private var showCreateSheet = false
    @State private var newCollectionName = ""

    var body: some View {
        NavigationStack {
            Group {
                if library.collections.isEmpty {
                    ContentUnavailableView(
                        "No Collections",
                        systemImage: "folder.badge.plus",
                        description: Text("Create collections to group your comics by theme, reading order, or any category you choose.")
                    )
                } else {
                    List {
                        ForEach(library.collections) { collection in
                            NavigationLink(destination: CollectionDetailView(collection: collection)) {
                                HStack {
                                    Image(systemName: "folder.fill")
                                        .foregroundStyle(Color.arcGold)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(collection.name).font(.body)
                                        Text("\(collection.comicCount) comic\(collection.comicCount == 1 ? "" : "s")")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, .arcS4)
                            }
                        }
                        .onDelete { indexSet in
                            for i in indexSet { library.deleteCollection(library.collections[i]) }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color.arcBg)
            .navigationTitle("Collections")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showCreateSheet = true } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .accessibilityLabel("Create collection")
                }
            }
            .onAppear { library.loadCollections() }
            .sheet(isPresented: $showCreateSheet) {
                createCollectionSheet
            }
        }
    }

    private var createCollectionSheet: some View {
        NavigationStack {
            Form {
                Section("Collection Name") {
                    TextField("My Collection", text: $newCollectionName)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.arcBg)
            .navigationTitle("New Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        newCollectionName = ""
                        showCreateSheet = false
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        let name = newCollectionName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        library.createCollection(name: name)
                        newCollectionName = ""
                        showCreateSheet = false
                    }
                    .fontWeight(.semibold)
                    .disabled(newCollectionName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.height(200)])
        .presentationDragIndicator(.visible)
    }
}

struct CollectionDetailView: View {
    @EnvironmentObject var library: LibraryViewModel
    let collection: Collection

    @State private var comics: [Comic] = []
    @State private var showAddSheet = false

    var body: some View {
        Group {
            if comics.isEmpty {
                ContentUnavailableView(
                    "Empty Collection",
                    systemImage: "folder",
                    description: Text("Add comics to \"\(collection.name)\" using the + button or from a comic's detail view.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, spacing: .arcS12) {
                        ForEach(comics) { comic in
                            ComicCard(comic: comic)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        removeComic(comic)
                                    } label: {
                                        Label("Remove from Collection", systemImage: "folder.badge.minus")
                                    }
                                }
                        }
                    }
                    .padding(.arcS12)
                }
            }
        }
        .background(Color.arcBg)
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAddSheet = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add comics")
            }
        }
        .onAppear { loadComics() }
        .sheet(isPresented: $showAddSheet, onDismiss: loadComics) {
            AddToCollectionSheet(collection: collection)
                .environmentObject(library)
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 140), spacing: .arcS12)]
    }

    private func loadComics() {
        let id = collection.id
        Task {
            let result = await Task.detached(priority: .utility) {
                DatabaseManager.shared.comics(inCollection: id)
            }.value
            comics = result
        }
    }

    private func removeComic(_ comic: Comic) {
        let collId = collection.id
        let comicId = comic.id
        Task {
            await Task.detached(priority: .userInitiated) {
                DatabaseManager.shared.removeFromCollection(collectionId: collId, comicId: comicId)
            }.value
            loadComics()
            library.loadCollections()
        }
    }
}

struct AddToCollectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var library: LibraryViewModel

    let collection: Collection

    @State private var search = ""
    @State private var alreadyInCollection: Set<Int64> = []

    private var filteredComics: [Comic] {
        guard !search.isEmpty else { return library.comics }
        let q = search.lowercased()
        return library.comics.filter {
            $0.title.lowercased().contains(q) || $0.series.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredComics) { comic in
                HStack {
                    CoverImage(comic: comic)
                        .frame(width: 36, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(comic.title).font(.subheadline)
                        Text(comic.series).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if alreadyInCollection.contains(comic.id) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.arcGold)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { toggle(comic) }
            }
            .listStyle(.plain)
            .searchable(text: $search, prompt: "Search comics")
            .background(Color.arcBg)
            .navigationTitle("Add to \"\(collection.name)\"")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { loadExisting() }
        }
    }

    private func loadExisting() {
        let id = collection.id
        Task {
            let ids = await Task.detached(priority: .utility) {
                DatabaseManager.shared.comics(inCollection: id).map(\.id)
            }.value
            alreadyInCollection = Set(ids)
        }
    }

    private func toggle(_ comic: Comic) {
        let collId = collection.id
        let comicId = comic.id
        if alreadyInCollection.contains(comicId) {
            alreadyInCollection.remove(comicId)
            Task {
                await Task.detached(priority: .userInitiated) {
                    DatabaseManager.shared.removeFromCollection(collectionId: collId, comicId: comicId)
                }.value
                library.loadCollections()
            }
        } else {
            alreadyInCollection.insert(comicId)
            library.addToCollection(collectionId: collId, comicId: comicId)
        }
    }
}

struct ComicCollectionPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var library: LibraryViewModel

    let comic: Comic

    @State private var membership: Set<Int64> = []

    var body: some View {
        NavigationStack {
            Group {
                if library.collections.isEmpty {
                    ContentUnavailableView(
                        "No Collections",
                        systemImage: "folder.badge.plus",
                        description: Text("Create a collection first from the Collections tab.")
                    )
                } else {
                    List(library.collections) { collection in
                        HStack {
                            Image(systemName: membership.contains(collection.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(membership.contains(collection.id) ? Color.arcGold : .secondary)
                            Text(collection.name)
                            Spacer()
                            Text("\(collection.comicCount)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { toggle(collectionId: collection.id) }
                    }
                    .listStyle(.plain)
                }
            }
            .background(Color.arcBg)
            .navigationTitle("Add to Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
            .onAppear { loadMembership() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func loadMembership() {
        let comicId = comic.id
        Task {
            let ids = await Task.detached(priority: .utility) {
                DatabaseManager.shared.collectionsContainingComic(comicId: comicId).map { $0 }
            }.value
            membership = Set(ids)
        }
    }

    private func toggle(collectionId: Int64) {
        let comicId = comic.id
        if membership.contains(collectionId) {
            membership.remove(collectionId)
            Task {
                await Task.detached(priority: .userInitiated) {
                    DatabaseManager.shared.removeFromCollection(collectionId: collectionId, comicId: comicId)
                }.value
                library.loadCollections()
            }
        } else {
            membership.insert(collectionId)
            library.addToCollection(collectionId: collectionId, comicId: comicId)
        }
    }
}
