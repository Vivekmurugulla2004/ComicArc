import UIKit

// MARK: - Page Image Cache

/// NSCache-backed store for decoded comic page images, keyed by "filePath:pageIndex".
/// Auto-evicted under memory pressure; capped at 24 pages / 150 MB.
final class PageImageCache: @unchecked Sendable {
    static let shared = PageImageCache()

    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit     = 24
        c.totalCostLimit = 150 * 1024 * 1024
        return c
    }()

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: nil
        ) { [weak self] _ in self?.cache.removeAllObjects() }
    }

    static func key(filePath: String, index: Int) -> String { "\(filePath):\(index)" }

    func image(for key: String) -> UIImage? { cache.object(forKey: key as NSString) }

    func setImage(_ img: UIImage, for key: String, cost: Int = 0) {
        cache.setObject(img, forKey: key as NSString, cost: cost)
    }

    func invalidateAll() {
        cache.removeAllObjects()
    }
}

// MARK: - Shared page loader

/// Loads a single decoded page image, checking PageImageCache first.
/// Returns nil for out-of-range indices or unsupported formats.
/// Must be called off the main thread (Task.detached / background).
func loadPageImage(comic: Comic, index: Int) async -> UIImage? {
    let key = PageImageCache.key(filePath: comic.filePath, index: index)
    if let cached = PageImageCache.shared.image(for: key) { return cached }
    let filePath = comic.filePath
    let ext      = comic.fileExtension
    let url      = URL(fileURLWithPath: filePath)
    let result: UIImage? = await Task.detached(priority: .userInitiated) {
        switch ext {
        case "cbz":                      return CBZReaderCache.shared.reader(for: filePath)?.image(at: index)
        case "cbr":                      return DirectoryReaderCache.shared.reader(for: filePath)?.image(at: index)
        case "pdf":                      return PDFPageCounter.image(url: url, at: index)
        case "jpg", "jpeg", "png":       return index == 0 ? UIImage(contentsOfFile: filePath) : nil
        default:                         return nil
        }
    }.value
    if let result {
        let cost = Int(result.size.width * result.scale * result.size.height * result.scale * 4)
        PageImageCache.shared.setImage(result, for: key, cost: cost)
    }
    return result
}

// MARK: - CBZ Reader Cache

/// Keeps up to 3 open CBZReader instances so sequential page loads don't re-open the ZIP archive.
final class CBZReaderCache: @unchecked Sendable {
    static let shared = CBZReaderCache()

    private var readers: [(path: String, reader: CBZReader)] = []
    private let lock = NSLock()
    private let capacity = 3

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: nil
        ) { [weak self] _ in self?.invalidateAll() }
    }

    func reader(for path: String) -> CBZReader? {
        lock.lock(); defer { lock.unlock() }
        if let idx = readers.firstIndex(where: { $0.path == path }) {
            let hit = readers.remove(at: idx)
            readers.append(hit)   // move to back = most-recently used
            return hit.reader
        }
        guard let reader = try? CBZReader(url: URL(fileURLWithPath: path)) else { return nil }
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
