import Foundation

struct Comic: Identifiable, Hashable {
    let id: Int64
    var title: String
    var filePath: String
    var publisher: String
    var character: String?
    var series: String
    var issueNumber: String?
    var pageCount: Int
    var progress: Int
    var rating: Int
    var isFavorite: Bool
    var inReadingList: Bool
    var tags: [String]
    var dateAdded: Date
    var writer: String?
    var penciller: String?
    var year: Int?
    var storyArc: String?
    var languageISO: String?
    var summary: String?
    var notes: String?
    var customCoverPath: String?

    var progressPercent: Double {
        guard pageCount > 0 else { return 0 }
        return Double(progress) / Double(pageCount)
    }

    var isFinished: Bool { pageCount > 1 && progress >= pageCount - 2 }
    var isStarted: Bool  { progress > 0 }

    var fileExtension: String {
        URL(fileURLWithPath: filePath).pathExtension.lowercased()
    }

    static func == (lhs: Comic, rhs: Comic) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct SeriesGroup: Identifiable {
    let id: String
    let groupName: String
    let character: String?
    let publisher: String
    let coverComicId: Int64
    let issueCount: Int
    let started: Int
    let completed: Int

    var isFinished: Bool { issueCount > 0 && completed == issueCount }
    var isReading: Bool  { started > 0 && !isFinished }
}

struct Collection: Identifiable {
    let id: Int64
    var name: String
    var comicCount: Int
}

struct SeriesMeta {
    var description: String
    var customCoverId: Int64?
}
