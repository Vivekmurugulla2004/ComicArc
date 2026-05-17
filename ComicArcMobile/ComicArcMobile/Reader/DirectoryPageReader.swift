import UIKit

/// Reads comic pages from a flat directory of image files (extracted CBR content).
/// Matches the image(at:)/pageCount interface used by CBZReader.
final class DirectoryPageReader: @unchecked Sendable {
    private let imagePaths: [String]
    nonisolated var pageCount: Int { imagePaths.count }

    private static let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "webp"]

    init(directory: URL) {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: .skipsHiddenFiles
        )) ?? []
        imagePaths = contents
            .filter { Self.imageExts.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent,
                                                   options: [.numeric, .caseInsensitive]) == .orderedAscending }
            .map(\.path)
    }

    nonisolated func image(at index: Int) -> UIImage? {
        guard index >= 0, index < imagePaths.count else { return nil }
        return UIImage(contentsOfFile: imagePaths[index])
    }
}

// MARK: - Directory Reader Cache

/// Keeps up to 3 open DirectoryPageReader instances to avoid rescanning directories on every page.
final class DirectoryReaderCache: @unchecked Sendable {
    static let shared = DirectoryReaderCache()

    private var readers: [(path: String, reader: DirectoryPageReader)] = []
    private let lock = NSLock()
    private let capacity = 3

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: nil
        ) { [weak self] _ in self?.invalidateAll() }
    }

    func reader(for path: String) -> DirectoryPageReader? {
        lock.lock(); defer { lock.unlock() }
        if let idx = readers.firstIndex(where: { $0.path == path }) {
            let hit = readers.remove(at: idx)
            readers.append(hit)   // move to back = most-recently used
            return hit.reader
        }
        let reader = DirectoryPageReader(directory: URL(fileURLWithPath: path))
        guard reader.pageCount > 0 else { return nil }
        if readers.count >= capacity { readers.removeFirst() }   // evict least-recently used
        readers.append((path: path, reader: reader))
        return reader
    }

    func invalidate(path: String) {
        lock.lock(); defer { lock.unlock() }
        readers.removeAll { $0.path == path }
    }

    func invalidateAll() {
        lock.lock(); defer { lock.unlock() }
        readers.removeAll()
    }
}
