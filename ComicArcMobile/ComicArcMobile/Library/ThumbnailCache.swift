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

    private init() {}

    /// Returns a cover image, generating and caching it on a background thread if needed.
    func thumbnail(comicId: Int64) async -> UIImage? {
        let key = NSNumber(value: comicId)
        if let hit = cache.object(forKey: key) { return hit }

        return await Task.detached(priority: .utility) { [self] in
            let diskURL = self.coversDir.appendingPathComponent("\(comicId).jpg")
            if let data = try? Data(contentsOf: diskURL), let img = UIImage(data: data) {
                self.cache.setObject(img, forKey: key)
                return img
            }

            guard let comic = self.db.comic(id: comicId) else { return nil }
            guard let img = self.generateCover(for: comic) else { return nil }
            if let data = img.jpegData(compressionQuality: 0.85) {
                try? data.write(to: diskURL)
            }
            self.cache.setObject(img, forKey: key)
            return img
        }.value
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
            return (try? CBZReader(url: url))?.image(at: 0)
        case "pdf":
            return PDFPageCounter.firstPage(url: url)
        case "jpg", "jpeg", "png":
            return UIImage(contentsOfFile: comic.filePath)
        default:
            return nil
        }
    }
}
