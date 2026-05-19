import Foundation

struct Comic: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var title: String
    var series: String
    var character: String?
    var publisher: String
    var issueNumber: String?
    var pageCount: Int
    var filePath: String
    var bookmarkData: Data?

    // ComicInfo.xml metadata
    var writer: String?
    var penciller: String?
    var year: Int?
    var storyArc: String?
    var languageISO: String?

    // User data
    var currentPage: Int = 0
    var lastRead: Date?
    var rating: Int = 0
    var isFavorite: Bool = false
    var inReadingList: Bool = false
    var addedAt: Date = Date()

    var progress: Double {
        guard pageCount > 0 else { return 0 }
        return Double(currentPage) / Double(pageCount)
    }

    var isFinished: Bool {
        pageCount > 0 && currentPage >= pageCount - 2
    }

    var isStarted: Bool { currentPage > 0 }
}

struct ReadingRun: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var description: String?
    var comicIds: [UUID] = []
    var rating: Int = 0
    var createdAt: Date = Date()
}

struct LibraryStats {
    var total: Int
    var completed: Int
    var inProgress: Int
    var pagesRead: Int
    var favorites: Int
    var runs: Int
    var byPublisher: [(publisher: String, count: Int)]
    var topSeries: [(series: String, count: Int)]
    var recentReads: [Comic]
    var activityMap: [String: Int]
}
