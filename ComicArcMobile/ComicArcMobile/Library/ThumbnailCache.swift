import UIKit

final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let cache: NSCache<NSNumber, UIImage> = {
        let c = NSCache<NSNumber, UIImage>()
        c.countLimit     = 200
        c.totalCostLimit = 100 * 1024 * 1024
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

    func thumbnail(comic: Comic) async -> UIImage? {
        let key = NSNumber(value: comic.id)
        if let hit = cache.object(forKey: key) { return hit }

        return await Task.detached(priority: .utility) { [self] in

            if let customPath = comic.customCoverPath,
               let img = UIImage(contentsOfFile: customPath) {
                let thumb = self.downsample(img, to: Self.thumbnailSize)
                self.cache.setObject(thumb, forKey: key, cost: self.cost(of: thumb))
                return thumb
            }

            let diskURL = self.coversDir.appendingPathComponent("\(comic.id).jpg")
            if let data = try? Data(contentsOf: diskURL), let img = UIImage(data: data) {
                self.cache.setObject(img, forKey: key, cost: self.cost(of: img))
                return img
            }

            guard let raw = self.generateCover(for: comic) else { return nil }
            let img = self.downsample(raw, to: Self.thumbnailSize)
            if let data = img.jpegData(compressionQuality: 0.85) {
                try? data.write(to: diskURL)
            }
            self.cache.setObject(img, forKey: key, cost: self.cost(of: img))
            return img
        }.value
    }

    func thumbnail(comicId: Int64) async -> UIImage? {
        let key = NSNumber(value: comicId)
        if let hit = cache.object(forKey: key) { return hit }

        return await Task.detached(priority: .utility) { [self] in
            let diskURL = self.coversDir.appendingPathComponent("\(comicId).jpg")
            if let data = try? Data(contentsOf: diskURL), let img = UIImage(data: data) {
                self.cache.setObject(img, forKey: key, cost: self.cost(of: img))
                return img
            }
            guard let comic = self.db.comic(id: comicId) else { return nil }

            if let customPath = comic.customCoverPath,
               let img = UIImage(contentsOfFile: customPath) {
                let thumb = self.downsample(img, to: Self.thumbnailSize)
                self.cache.setObject(thumb, forKey: key, cost: self.cost(of: thumb))
                return thumb
            }
            guard let raw = self.generateCover(for: comic) else { return nil }
            let img = self.downsample(raw, to: Self.thumbnailSize)
            if let data = img.jpegData(compressionQuality: 0.85) {
                try? data.write(to: diskURL)
            }
            self.cache.setObject(img, forKey: key, cost: self.cost(of: img))
            return img
        }.value
    }

    func setCustomCover(comicId: Int64, image: UIImage) async {
        await Task.detached(priority: .userInitiated) { [self] in
            let customDir = self.coversDir.appendingPathComponent("custom")
            try? FileManager.default.createDirectory(at: customDir, withIntermediateDirectories: true)
            let path = customDir.appendingPathComponent("\(comicId).jpg").path
            if let data = image.jpegData(compressionQuality: 0.9) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
            self.db.setCustomCoverPath(id: comicId, path: path)

            self.invalidate(comicId: comicId)
        }.value
    }

    func clearCustomCover(comicId: Int64) {
        let customPath = coversDir.appendingPathComponent("custom/\(comicId).jpg").path
        try? FileManager.default.removeItem(atPath: customPath)
        db.setCustomCoverPath(id: comicId, path: nil)
        invalidate(comicId: comicId)
    }

    func invalidate(comicId: Int64) {
        cache.removeObject(forKey: NSNumber(value: comicId))
        let diskURL = coversDir.appendingPathComponent("\(comicId).jpg")
        try? FileManager.default.removeItem(at: diskURL)
    }

    func invalidateAll() {
        cache.removeAllObjects()
    }

    private func cost(of image: UIImage) -> Int {
        Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }

    private func downsample(_ image: UIImage, to targetSize: CGSize) -> UIImage {
        let scale = UIScreen.main.scale
        let targetPx = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
        let srcSize  = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard srcSize.width > targetPx.width || srcSize.height > targetPx.height else { return image }
        let ratio    = min(targetPx.width / srcSize.width, targetPx.height / srcSize.height)
        let drawSize = CGSize(width: (srcSize.width * ratio) / scale, height: (srcSize.height * ratio) / scale)
        return UIGraphicsImageRenderer(size: drawSize, format: {
            let f = UIGraphicsImageRendererFormat(); f.scale = scale; f.opaque = true; return f
        }()).image { _ in image.draw(in: CGRect(origin: .zero, size: drawSize)) }
    }

    private func generateCover(for comic: Comic) -> UIImage? {
        let url = URL(fileURLWithPath: comic.filePath)
        switch comic.fileExtension {
        case "cbz":            return CBZReaderCache.shared.reader(for: comic.filePath)?.image(at: 0)
        case "cbr":            return DirectoryReaderCache.shared.reader(for: comic.filePath)?.image(at: 0)
        case "pdf":            return PDFPageCounter.firstPage(url: url)
        case "jpg", "jpeg", "png": return UIImage(contentsOfFile: comic.filePath)
        default:               return nil
        }
    }
}
