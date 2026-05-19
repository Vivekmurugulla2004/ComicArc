import Foundation
import UIKit
import PDFKit
import Compression
import ZipFoundation

// MARK: - ComicInfo.xml

struct ComicInfoXML {
    var series: String?
    var publisher: String?
    var writer: String?
    var penciller: String?
    var year: Int?
    var storyArc: String?
    var issueNumber: String?
    var languageISO: String?
}

// MARK: - ZipReader (lightweight CBZ support without ZipFoundation)

final class ZipReader {
    private let data: Data

    init?(url: URL) {
        guard let d = try? Data(contentsOf: url) else { return nil }
        self.data = d
    }

    struct Entry {
        let name: String
        let offset: Int
        let compressedSize: Int
        let uncompressedSize: Int
        let method: UInt16
    }

    lazy var entries: [Entry] = parseEntries()

    private func parseEntries() -> [Entry] {
        var result: [Entry] = []
        let bytes = [UInt8](data)
        let len = bytes.count
        // Scan for End of Central Directory (signature 0x06054b50)
        var eocdOffset = -1
        for i in stride(from: len - 22, through: max(0, len - 65558), by: -1) {
            if bytes[i] == 0x50 && bytes[i+1] == 0x4b && bytes[i+2] == 0x05 && bytes[i+3] == 0x06 {
                eocdOffset = i; break
            }
        }
        guard eocdOffset >= 0 else { return result }
        let cdCount  = Int(u16(bytes, eocdOffset + 8))
        let cdOffset = Int(u32(bytes, eocdOffset + 16))

        var pos = cdOffset
        for _ in 0..<cdCount {
            guard pos + 46 <= len else { break }
            guard bytes[pos] == 0x50 && bytes[pos+1] == 0x4b && bytes[pos+2] == 0x01 && bytes[pos+3] == 0x02 else { break }
            let method           = u16(bytes, pos + 10)
            let compressedSize   = Int(u32(bytes, pos + 20))
            let uncompressedSize = Int(u32(bytes, pos + 24))
            let nameLen          = Int(u16(bytes, pos + 28))
            let extraLen         = Int(u16(bytes, pos + 30))
            let commentLen       = Int(u16(bytes, pos + 32))
            let localOffset      = Int(u32(bytes, pos + 42))
            if pos + 46 + nameLen <= len, let name = String(bytes: bytes[(pos+46)..<(pos+46+nameLen)], encoding: .utf8) {
                result.append(Entry(name: name, offset: localOffset, compressedSize: compressedSize,
                                    uncompressedSize: uncompressedSize, method: method))
            }
            pos += 46 + nameLen + extraLen + commentLen
        }
        return result
    }

    func read(entry: Entry) -> Data? {
        let bytes = [UInt8](data)
        let lhStart = entry.offset
        guard lhStart + 30 <= bytes.count else { return nil }
        guard bytes[lhStart] == 0x50 && bytes[lhStart+1] == 0x4b && bytes[lhStart+2] == 0x03 && bytes[lhStart+3] == 0x04 else { return nil }
        let nameLen  = Int(u16(bytes, lhStart + 26))
        let extraLen = Int(u16(bytes, lhStart + 28))
        let dataStart = lhStart + 30 + nameLen + extraLen
        guard dataStart + entry.compressedSize <= bytes.count else { return nil }
        let compressed = Data(bytes[dataStart..<(dataStart + entry.compressedSize)])
        if entry.method == 0 { return compressed }
        if entry.method == 8 { return inflate(compressed, uncompressedSize: entry.uncompressedSize) }
        return nil
    }

    private func inflate(_ data: Data, uncompressedSize: Int) -> Data? {
        var dst = Data(count: uncompressedSize)
        let result = dst.withUnsafeMutableBytes { dstPtr in
            data.withUnsafeBytes { srcPtr in
                compression_decode_buffer(
                    dstPtr.bindMemory(to: UInt8.self).baseAddress!, uncompressedSize,
                    srcPtr.bindMemory(to: UInt8.self).baseAddress!, data.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        return result == uncompressedSize ? dst : nil
    }

    private func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
        UInt16(b[i]) | (UInt16(b[i+1]) << 8)
    }
    private func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | (UInt32(b[i+1]) << 8) | (UInt32(b[i+2]) << 16) | (UInt32(b[i+3]) << 24)
    }
}

// MARK: - Comic page reading

enum ComicReader {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp"]

    static func pageCount(url: URL) -> Int {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "cbz":  return cbzPageCount(url: url)
        case "pdf":  return pdfPageCount(url: url)
        case "jpg", "jpeg", "png", "gif", "webp", "bmp": return 1
        default: return 0
        }
    }

    static func page(url: URL, index: Int) -> UIImage? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "cbz":  return cbzPage(url: url, index: index)
        case "pdf":  return pdfPage(url: url, index: index)
        case "jpg", "jpeg", "png", "gif", "webp", "bmp":
            return index == 0 ? UIImage(contentsOfFile: url.path) : nil
        default: return nil
        }
    }

    static func comicInfo(url: URL) -> ComicInfoXML? {
        guard url.pathExtension.lowercased() == "cbz",
              let zip = ZipReader(url: url) else { return nil }
        guard let entry = zip.entries.first(where: { $0.name.lowercased().hasSuffix("comicinfo.xml") }),
              let xmlData = zip.read(entry: entry) else { return nil }
        return parseComicInfo(xmlData)
    }

    // MARK: - Private CBZ

    private static func imageEntries(_ zip: ZipReader) -> [ZipReader.Entry] {
        zip.entries
            .filter { imageExtensions.contains($0.name.pathExtension.lowercased()) && !$0.name.hasPrefix(".") }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func cbzPageCount(url: URL) -> Int {
        guard let zip = ZipReader(url: url) else { return 0 }
        return imageEntries(zip).count
    }

    private static func cbzPage(url: URL, index: Int) -> UIImage? {
        guard let zip = ZipReader(url: url) else { return nil }
        let imgs = imageEntries(zip)
        guard index < imgs.count, let data = zip.read(entry: imgs[index]) else { return nil }
        return UIImage(data: data)
    }

    // MARK: - Private PDF

    private static func pdfPageCount(url: URL) -> Int {
        PDFDocument(url: url)?.pageCount ?? 0
    }

    private static func pdfPage(url: URL, index: Int) -> UIImage? {
        guard let doc = PDFDocument(url: url), index < doc.pageCount,
              let page = doc.page(at: index) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            ctx.cgContext.setFillColor(UIColor.white.cgColor)
            ctx.cgContext.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.scaleBy(x: scale, y: scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }

    // MARK: - ComicInfo.xml parsing

    private static func parseComicInfo(_ data: Data) -> ComicInfoXML? {
        guard let str = String(data: data, encoding: .utf8) else { return nil }
        func extract(_ tag: String) -> String? {
            guard let r = str.range(of: "<\(tag)>"),
                  let end = str.range(of: "</\(tag)>", range: r.upperBound..<str.endIndex) else { return nil }
            return String(str[r.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var info = ComicInfoXML()
        info.series      = extract("Series")
        info.publisher   = extract("Publisher")
        info.writer      = extract("Writer")
        info.penciller   = extract("Penciller")
        info.storyArc    = extract("StoryArc")
        info.languageISO = extract("LanguageISO")
        info.issueNumber = extract("Number")
        if let y = extract("Year"), let yi = Int(y) { info.year = yi }
        return info
    }
}

private extension String {
    var pathExtension: String {
        (self as NSString).pathExtension
    }
}
