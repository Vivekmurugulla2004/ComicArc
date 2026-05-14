import Foundation
import ZIPFoundation

struct ComicInfo {
    var series: String?
    var number: String?
    var publisher: String?
    var writer: String?
    var summary: String?
    var characters: [String] = []
}

/// Reads ComicInfo.xml from CBZ archives (standard comic metadata format).
/// The file may be at the archive root or one level deep.
enum ComicInfoParser {
    static func parse(cbzURL: URL) -> ComicInfo? {
        guard let archive = try? Archive(url: cbzURL, accessMode: .read) else { return nil }
        let entry = archive.first(where: {
            let lower = $0.path.lowercased()
            return lower == "comicinfo.xml" || lower.hasSuffix("/comicinfo.xml")
        })
        guard let entry else { return nil }
        var data = Data()
        _ = try? archive.extract(entry, consumer: { data.append($0) })
        guard !data.isEmpty else { return nil }
        return XMLInfoParser.parse(data: data)
    }
}

private final class XMLInfoParser: NSObject, XMLParserDelegate {
    private(set) var info = ComicInfo()
    private var buffer = ""

    static func parse(data: Data) -> ComicInfo {
        let parser = XMLParser(data: data)
        let delegate = XMLInfoParser()
        parser.delegate = delegate
        parser.parse()
        return delegate.info
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let v = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !v.isEmpty else { return }
        switch elementName {
        case "Series":    info.series    = v
        case "Number":    info.number    = v
        case "Publisher": info.publisher = v
        case "Writer":    info.writer    = v
        case "Summary":   info.summary   = v
        case "Characters":
            info.characters = v.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        default: break
        }
    }
}
