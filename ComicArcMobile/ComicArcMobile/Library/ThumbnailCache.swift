import UIKit

final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let cache: NSCache<NSNumber, UIImage> = {
        let c = NSCache<NSNumber, UIImage>()
        c.countLimit       = 200
        c.totalCostLimit   = 100 * 1024 * 1024   // 100 MB
        return c
    }()

    private let db = DatabaseManager.shared

    private let coversDir: URL = {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ComicArc/covers")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: nil
        ) { [weak self] _ in self?.cache.removeAllObjects() }
    }

    private static let thumbnailSize = CGSize(width: 300, height: 450)

    /// Fast path — caller already has the Comic struct, so no DB lookup needed.
    /// Use this from all grid/list contexts where the Comic is already in memory.
    func thumbnail(comic: Comic) async -> UIImage? {
        let key = NSNumber(value: comic.id)
        if let hit = cache.object(forKey: key) { return hit }

        return await Task.detached(priority: .utility) { [self] in
            let diskURL = self.coversDir.appendingPathComponent("\(comic.id).jpg")
            if let data = try? Data(contentsOf: diskURL), let img = UIImage(data: data) {
                self.cache.setObject(img, forKey: key,
                                     cost: Int(img.size.width * img.scale * img.size.height * img.scale * 4))
                return img
            }
            guard let raw = self.generateCover(for: comic) else { return nil }
            let img = self.downsample(raw, to: Self.thumbnailSize)
            if let data = img.jpegData(compressionQuality: 0.85) {
                try? data.write(to: diskURL)
            }
            let cost = Int(img.size.width * img.scale * img.size.height * img.scale * 4)
            self.cache.setObject(img, forKey: key, cost: cost)
            return img
        }.value
    }

    /// Fallback path — only use when the full Comic struct isn't available (e.g. series cover by id).
    func thumbnail(comicId: Int64) async -> UIImage? {
        let key = NSNumber(value: comicId)
        if let hit = cache.object(forKey: key) { return hit }

        return await Task.detached(priority: .utility) { [self] in
            let diskURL = self.coversDir.appendingPathComponent("\(comicId).jpg")
            if let data = try? Data(contentsOf: diskURL), let img = UIImage(data: data) {
                self.cache.setObject(img, forKey: key,
                                     cost: Int(img.size.width * img.scale * img.size.height * img.scale * 4))
                return img
            }
            guard let comic = self.db.comic(id: comicId) else { return nil }
            guard let raw = self.generateCover(for: comic) else { return nil }
            let img = self.downsample(raw, to: Self.thumbnailSize)
            if let data = img.jpegData(compressionQuality: 0.85) {
                try? data.write(to: diskURL)
            }
            let cost = Int(img.size.width * img.scale * img.size.height * img.scale * 4)
            self.cache.setObject(img, forKey: key, cost: cost)
            return img
        }.value
    }

    private func downsample(_ image: UIImage, to targetSize: CGSize) -> UIImage {
        let scale = UIScreen.main.scale
        let targetPx = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
        let srcSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard srcSize.width > targetPx.width || srcSize.height > targetPx.height else { return image }
        let ratio = min(targetPx.width / srcSize.width, targetPx.height / srcSize.height)
        let drawSize = CGSize(width: (srcSize.width * ratio) / scale, height: (srcSize.height * ratio) / scale)
        return UIGraphicsImageRenderer(size: drawSize, format: {
            let f = UIGraphicsImageRendererFormat()
            f.scale = scale
            f.opaque = true
            return f
        }()).image { _ in image.draw(in: CGRect(origin: .zero, size: drawSize)) }
    }

    func invalidate(comicId: Int64) {
        cache.removeObject(forKey: NSNumber(value: comicId))
        let diskURL = coversDir.appendingPathComponent("\(comicId).jpg")
        try? FileManager.default.removeItem(at: diskURL)
    }

    func invalidateAll() {
        cache.removeAllObjects()
    }

    private func generateCover(for comic: Comic) -> UIImage? {
        let url = URL(fileURLWithPath: comic.filePath)
        switch comic.fileExtension {
        case "cbz":
            return CBZReaderCache.shared.reader(for: comic.filePath)?.image(at: 0)
        case "cbr":
            return DirectoryReaderCache.shared.reader(for: comic.filePath)?.image(at: 0)
        case "pdf":
            return PDFPageCounter.firstPage(url: url)
        case "jpg", "jpeg", "png":
            return UIImage(contentsOfFile: comic.filePath)
        default:
            return nil
        }
    }
}
