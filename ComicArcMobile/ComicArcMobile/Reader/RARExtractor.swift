import Foundation

private typealias ArchivePtr      = OpaquePointer
private typealias ArchiveEntryPtr = OpaquePointer

@_silgen_name("archive_read_new")
private func _archive_read_new() -> ArchivePtr?
@discardableResult @_silgen_name("archive_read_support_filter_all")
private func _archive_read_support_filter_all(_ a: ArchivePtr?) -> Int32
@discardableResult @_silgen_name("archive_read_support_format_rar")
private func _archive_read_support_format_rar(_ a: ArchivePtr?) -> Int32
@discardableResult @_silgen_name("archive_read_support_format_rar5")
private func _archive_read_support_format_rar5(_ a: ArchivePtr?) -> Int32
@_silgen_name("archive_read_open_filename")
private func _archive_read_open_filename(_ a: ArchivePtr?, _ filename: UnsafePointer<CChar>?, _ blockSize: Int) -> Int32
@_silgen_name("archive_read_next_header")
private func _archive_read_next_header(_ a: ArchivePtr?, _ entry: UnsafeMutablePointer<ArchiveEntryPtr?>) -> Int32
@_silgen_name("archive_entry_pathname")
private func _archive_entry_pathname(_ entry: ArchiveEntryPtr?) -> UnsafePointer<CChar>?
@_silgen_name("archive_entry_size")
private func _archive_entry_size(_ entry: ArchiveEntryPtr?) -> Int64
@_silgen_name("archive_read_data")
private func _archive_read_data(_ a: ArchivePtr?, _ buff: UnsafeMutableRawPointer?, _ size: Int) -> Int
@discardableResult @_silgen_name("archive_read_data_skip")
private func _archive_read_data_skip(_ a: ArchivePtr?) -> Int32
@discardableResult @_silgen_name("archive_read_free")
private func _archive_read_free(_ a: ArchivePtr?) -> Int32
@_silgen_name("archive_error_string")
private func _archive_error_string(_ a: ArchivePtr?) -> UnsafePointer<CChar>?

private let ARCHIVE_OK  = Int32(0)
private let ARCHIVE_EOF = Int32(1)

enum RARExtractorError: Error, LocalizedError {
    case openFailed(String)
    case noImages

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "Could not open RAR archive: \(msg)"
        case .noImages:            return "No images found in CBR archive."
        }
    }
}

struct RARExtractor {
    private static let imageExts: Set<String> = ["jpg", "jpeg", "png", "gif", "webp"]
    private static let chunkSize = 65_536

    static func extract(archiveURL: URL, destination: URL) throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        guard let a = _archive_read_new() else {
            throw RARExtractorError.openFailed("archive_read_new returned nil")
        }
        defer { _archive_read_free(a) }

        _archive_read_support_filter_all(a)
        _archive_read_support_format_rar(a)
        _archive_read_support_format_rar5(a)

        let rc = archiveURL.path.withCString { ptr in
            _archive_read_open_filename(a, ptr, chunkSize)
        }
        guard rc == ARCHIVE_OK else {
            let msg = _archive_error_string(a).map { String(cString: $0) } ?? "unknown error"
            throw RARExtractorError.openFailed(msg)
        }

        var extractedURLs: [URL] = []
        var entry: ArchiveEntryPtr?
        var seenNames: [String: Int] = [:]

        while _archive_read_next_header(a, &entry) == ARCHIVE_OK {
            guard let e = entry,
                  let rawPath = _archive_entry_pathname(e) else {
                _archive_read_data_skip(a)
                continue
            }
            let entryName = String(cString: rawPath)
            let ext = URL(fileURLWithPath: entryName).pathExtension.lowercased()
            guard imageExts.contains(ext) else {
                _archive_read_data_skip(a)
                continue
            }

            let baseName = URL(fileURLWithPath: entryName).lastPathComponent
            let destName: String
            if let count = seenNames[baseName] {
                let stem = URL(fileURLWithPath: baseName).deletingPathExtension().lastPathComponent
                destName = "\(stem)_\(count).\(ext)"
                seenNames[baseName] = count + 1
            } else {
                destName = baseName
                seenNames[baseName] = 1
            }
            let destURL = destination.appendingPathComponent(destName)
            if streamEntry(archive: a, to: destURL) {
                extractedURLs.append(destURL)
            }
        }

        guard !extractedURLs.isEmpty else { throw RARExtractorError.noImages }

        return extractedURLs.sorted {
            $0.lastPathComponent.compare($1.lastPathComponent,
                                         options: [.numeric, .caseInsensitive]) == .orderedAscending
        }
    }

    private static func streamEntry(archive a: ArchivePtr, to dest: URL) -> Bool {
        FileManager.default.createFile(atPath: dest.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: dest) else {
            try? FileManager.default.removeItem(at: dest)
            return false
        }
        defer { try? handle.close() }

        var buffer = [UInt8](repeating: 0, count: chunkSize)
        var totalRead = 0
        while true {
            let read = buffer.withUnsafeMutableBytes { ptr in
                _archive_read_data(a, ptr.baseAddress, chunkSize)
            }
            guard read > 0 else { break }
            handle.write(Data(buffer[..<read]))
            totalRead += read
        }
        if totalRead == 0 {
            try? handle.close()
            try? FileManager.default.removeItem(at: dest)
            return false
        }
        return true
    }
}
