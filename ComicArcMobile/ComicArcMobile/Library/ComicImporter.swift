import Foundation

struct ComicMeta {
    var title: String
    var publisher: String
    var character: String?
    var series: String
    var issueNumber: String?
}

enum ComicImporter {
    private static let issueRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?:v|vol|volume|#|issue)[\s.]?(\d+)"#,
        options: .caseInsensitive
    )

    /// Derive metadata from the file URL — mirrors the desktop scanner's _meta() logic.
    /// Expected folder layout: Publisher/Character/Series/file.cbz
    static func parse(url: URL) -> ComicMeta {
        let filename = url.deletingPathExtension().lastPathComponent

        // Strip the app's Documents/Comics prefix to get relative parts
        let docsPath = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Comics").path

        var relative = url.path
        if relative.hasPrefix(docsPath) {
            relative = String(relative.dropFirst(docsPath.count))
        }
        let parts = relative.split(separator: "/").map(String.init).filter { !$0.isEmpty }

        let publisher: String
        let character: String?
        let series: String

        // parts = [Publisher, Character, Series, file] or fewer
        if parts.count >= 4 {
            publisher = parts[0]
            character = parts[parts.count - 3]
            series    = parts[parts.count - 2]
        } else if parts.count == 3 {
            publisher = parts[0]
            character = nil
            series    = parts[1]
        } else if parts.count == 2 {
            publisher = parts[0]
            character = nil
            series    = "General"
        } else {
            publisher = "Unknown"
            character = nil
            series    = "General"
        }

        // Extract issue number from filename
        var issueNumber: String?
        if let match = Self.issueRegex?.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
           let range = Range(match.range(at: 1), in: filename) {
            issueNumber = String(filename[range])
        }

        return ComicMeta(
            title: filename,
            publisher: publisher,
            character: character,
            series: series,
            issueNumber: issueNumber
        )
    }

    /// Returns page count without caching — call off main thread.
    static func pageCount(url: URL) async -> Int {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "cbz":
            return (try? CBZReader(url: url))?.pageCount ?? 0
        case "pdf":
            return PDFPageCounter.count(url: url)
        case "jpg", "jpeg", "png", "gif", "webp":
            return 1
        default:
            return 0
        }
    }
}
