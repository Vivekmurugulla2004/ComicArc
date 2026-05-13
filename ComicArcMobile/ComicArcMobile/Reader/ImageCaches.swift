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

    private init() {}

    static func key(filePath: String, index: Int) -> String { "\(filePath):\(index)" }

    func image(for key: String) -> UIImage? { cache.object(forKey: key as NSString) }

    func setImage(_ img: UIImage, for key: String, cost: Int = 0) {
        cache.setObject(img, forKey: key as NSString, cost: cost)
    }

    func invalidate(filePath: String) {
        // NSCache has no enumeration API; clear all and let it repopulate
        cache.removeAllObjects()
        _ = filePath  // suppress unused-variable warning
    }
}

// MARK: - CBZ Reader Cache

/// Keeps up to 3 open CBZReader instances so sequential page loads don't re-open the ZIP archive.
final class CBZReaderCache: @unchecked Sendable {
    static let shared = CBZReaderCache()

    private var readers: [(path: String, reader: CBZReader)] = []
    private let lock = NSLock()
    private let capacity = 3

    private init() {}

    func reader(for path: String) -> CBZReader? {
        lock.lock(); defer { lock.unlock() }
        if let hit = readers.first(where: { $0.path == path }) {
            return hit.reader
        }
        guard let reader = try? CBZReader(url: URL(fileURLWithPath: path)) else { return nil }
        if readers.count >= capacity { readers.removeFirst() }
        readers.append((path: path, reader: reader))
        return reader
    }

    func invalidate(path: String) {
        lock.lock(); defer { lock.unlock() }
        readers.removeAll { $0.path == path }
    }
}
