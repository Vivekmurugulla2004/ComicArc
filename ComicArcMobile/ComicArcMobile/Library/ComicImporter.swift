import Foundation

struct ComicMeta {
    var title: String
    var publisher: String
    var character: String?
    var series: String
    var issueNumber: String?
    var writer: String?
    var summary: String?
}

enum ComicImporter {
    private static let issueRegex: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?:v|vol|volume|#|issue)[\s.]?(\d+)"#,
        options: .caseInsensitive
    )

    static func parse(url: URL) -> ComicMeta {
        var meta = pathMeta(url: url)

        if url.pathExtension.lowercased() == "cbz",
           let info = ComicInfoParser.parse(cbzURL: url) {
            if let s = info.series,    !s.isEmpty { meta.series = s }
            if let p = info.publisher, !p.isEmpty { meta.publisher = p }
            if let n = info.number,    !n.isEmpty { meta.issueNumber = n }
            if let c = info.characters.first       { meta.character = c }
            meta.writer  = info.writer
            meta.summary = info.summary
        }

        return meta
    }

    static func pageCount(url: URL) async -> Int {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "cbz":
            return CBZReaderCache.shared.reader(for: url.path)?.pageCount ?? 0
        case "cbr":

            return DirectoryReaderCache.shared.reader(for: url.path)?.pageCount ?? 0
        case "pdf":
            return PDFPageCounter.count(url: url)
        case "jpg", "jpeg", "png", "gif", "webp":
            return 1
        default:
            return 0
        }
    }

    private static func pathMeta(url: URL) -> ComicMeta {
        let filename = url.deletingPathExtension().lastPathComponent

        let docsPath = (FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Comics").path

        var relative = url.path
        if relative.hasPrefix(docsPath) {
            relative = String(relative.dropFirst(docsPath.count))
        }
        let parts = relative.split(separator: "/").map(String.init).filter { !$0.isEmpty }

        let publisher: String
        let character: String?
        let series: String

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

        var issueNumber: String?
        if let match = issueRegex?.firstMatch(in: filename, range: NSRange(filename.startIndex..., in: filename)),
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
}
