import UIKit

actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private var cache: [Int64: UIImage] = [:]
    private let db = DatabaseManager.shared

    private var coversDir: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ComicArc/covers")
    }

    private init() {
        try? FileManager.default.createDirectory(at: coversDir, withIntermediateDirectories: true)
    }

    func thumbnail(comicId: Int64) -> UIImage? {
        if let cached = cache[comicId] { return cached }

        let diskURL = coversDir.appendingPathComponent("\(comicId).jpg")
        if let data = try? Data(contentsOf: diskURL), let img = UIImage(data: data) {
            cache[comicId] = img
            return img
        }

        guard let comic = db.comic(id: comicId) else { return nil }
        let img = generateCover(for: comic)
        if let img, let data = img.jpegData(compressionQuality: 0.85) {
            try? data.write(to: diskURL)
            cache[comicId] = img
        }
        return img
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
