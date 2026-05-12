import UIKit
import ZIPFoundation

final class CBZReader {
    private let archive: Archive
    private let entries: [Entry]

    var pageCount: Int { entries.count }

    init(url: URL) throws {
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.archive = archive
        self.entries = archive
            .filter { isImagePath($0.path) }
            .sorted { naturalSort($0.path, $1.path) }
    }

    func image(at index: Int) -> UIImage? {
        guard index >= 0, index < entries.count else { return nil }
        var data = Data()
        _ = try? archive.extract(entries[index], consumer: { data.append($0) })
        return UIImage(data: data)
    }

    // MARK: - Helpers

    private func isImagePath(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "webp"].contains(ext)
    }

    // Natural sort so "page10" comes after "page9"
    private func naturalSort(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: [.numeric, .caseInsensitive]) == .orderedAscending
    }
}
