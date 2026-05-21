import SwiftUI
import SQLite3

struct StatsView: View {
    @EnvironmentObject var library: LibraryViewModel
    @State private var stats: LibraryStats?

    var body: some View {
        NavigationStack {
            Group {
                if let s = stats {
                    List {
                        Section {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                statTile("Comics",     value: "\(s.totalComics)",                   icon: "books.vertical",  color: .arcGold)
                                statTile("Finished",   value: "\(s.finished)",                      icon: "checkmark.circle.fill", color: .green)
                                statTile("In Progress",value: "\(s.inProgress)",                    icon: "clock",           color: .arcGold)
                                statTile("Pages Read", value: formattedInt(s.pagesRead),            icon: "doc.text",        color: .arcBlue)
                                statTile("Favorites",  value: "\(s.favorites)",                     icon: "heart.fill",      color: .arcRed)
                                statTile("Runs",       value: "\(s.runsCount)",                     icon: "list.number",     color: .purple)
                            }
                            .listRowInsets(.init())
                            .listRowBackground(Color.clear)
                        }

                        Section("Reading Status") {
                            completionRow("Finished",    count: s.finished,    total: s.totalComics, color: .green)
                            completionRow("In Progress", count: s.inProgress,  total: s.totalComics, color: .arcGold)
                            completionRow("Unread",      count: s.unread,      total: s.totalComics, color: .secondary)
                        }

                        Section("Reading Activity") {
                            HStack(spacing: 14) {
                                Image(systemName: s.readingStreak > 0 ? "flame.fill" : "flame")
                                    .font(.title2)
                                    .foregroundStyle(s.readingStreak > 0 ? Color.orange : Color.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        Text("\(s.readingStreak)")
                                            .font(.title2.bold())
                                        Text("day streak")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text(s.readingStreak > 0
                                         ? "\(s.readingStreak) consecutive day\(s.readingStreak == 1 ? "" : "s") of reading"
                                         : "Open a comic today to start a streak")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)

                            if !s.activityMap.isEmpty {
                                ReadingHeatmap(activityMap: s.activityMap)
                                    .listRowInsets(.init(top: 0, leading: 0, bottom: 0, trailing: 0))
                                    .listRowBackground(Color.clear)
                            }
                        }

                        if !s.publisherBreakdown.isEmpty {
                            Section("By Publisher") {
                                ForEach(s.publisherBreakdown, id: \.publisher) { row in
                                    publisherRow(row, total: s.totalComics)
                                }
                            }
                        }

                        if !s.topSeries.isEmpty {
                            Section("Top Series by Issue Count") {
                                ForEach(Array(s.topSeries.enumerated()), id: \.offset) { i, row in
                                    HStack {
                                        Text("\(i + 1)")
                                            .font(.caption).foregroundStyle(.secondary)
                                            .frame(width: 20, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(row.series).font(.subheadline)
                                            Text(row.publisher).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text("\(row.count)")
                                            .font(.subheadline.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        if !s.recentlyRead.isEmpty {
                            Section("Recently Read") {
                                ForEach(s.recentlyRead) { comic in
                                    HStack(spacing: 12) {
                                        CoverImage(comic: comic)
                                            .frame(width: 36, height: 52)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(comic.title).font(.subheadline).lineLimit(1)
                                            if comic.pageCount > 0 {
                                                Text("p. \(comic.progress + 1) / \(comic.pageCount)")
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if comic.isFinished {
                                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                        }
                                    }
                                }
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Stats")
            .scrollContentBackground(.hidden)
            .background(Color.arcBg)
            .task { await loadStats() }
            .refreshable { await loadStats() }
        }
    }

    private func loadStats() async {
        let loaded = await Task.detached(priority: .utility) { LibraryStats.load() }.value
        stats = loaded
    }

    private func formattedInt(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func statTile(_ label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3).foregroundStyle(color)
            Text(value).font(.title3.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .arcCard()
    }

    private func completionRow(_ label: String, count: Int, total: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(count)").foregroundStyle(.secondary)
            }
            .font(.subheadline)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.arcBorder)
                Capsule()
                    .fill(color)
                    .scaleEffect(x: total > 0 ? CGFloat(count) / CGFloat(total) : 0, y: 1, anchor: .leading)
            }
            .frame(height: 6)
        }
        .padding(.vertical, 2)
    }

    private func publisherRow(_ row: PublisherStat, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.publisher)
                Spacer()
                Text("\(row.count)").foregroundStyle(.secondary)
            }
            .font(.subheadline)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.arcBorder)
                Capsule()
                    .fill(Color.arcGold)
                    .scaleEffect(x: total > 0 ? CGFloat(row.count) / CGFloat(total) : 0, y: 1, anchor: .leading)
            }
            .frame(height: 6)
        }
        .padding(.vertical, 2)
    }
}

struct ReadingHeatmap: View {
    let activityMap: [String: Int]

    private let cols = 18
    private let rows = 7
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Past \(cols) weeks")
                .font(.caption2)
                .foregroundStyle(Color.arcMuted)
                .padding(.horizontal, 16)
                .padding(.top, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(0..<cols, id: \.self) { col in
                        VStack(spacing: 3) {
                            ForEach(0..<rows, id: \.self) { row in
                                let date = dateFor(col: col, row: row)
                                let count = activityMap[date] ?? 0
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(heatColor(count))
                                    .frame(width: 13, height: 13)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            HStack(spacing: 4) {
                Text("Less").font(.caption2).foregroundStyle(Color.arcMuted)
                ForEach(0...4, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(heatColor(level == 0 ? 0 : level == 1 ? 1 : level == 2 ? 2 : level == 3 ? 4 : 6))
                        .frame(width: 11, height: 11)
                }
                Text("More").font(.caption2).foregroundStyle(Color.arcMuted)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
    }

    private func dateFor(col: Int, row: Int) -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let totalDays = cols * rows
        let daysAgo = totalDays - 1 - (col * rows + row)
        guard let date = cal.date(byAdding: .day, value: -daysAgo, to: today) else { return "" }
        return Self.dateFmt.string(from: date)
    }

    private func heatColor(_ count: Int) -> Color {
        switch count {
        case 0:    return Color.arcSurface
        case 1:    return Color(red: 0.10, green: 0.28, blue: 0.19)
        case 2...3: return Color(red: 0.18, green: 0.42, blue: 0.31)
        case 4...5: return Color(red: 0.25, green: 0.57, blue: 0.42)
        default:   return Color(red: 0.32, green: 0.72, blue: 0.53)
        }
    }
}

struct PublisherStat { let publisher: String; let count: Int }
struct SeriesStat     { let series: String; let publisher: String; let count: Int }

struct LibraryStats {
    let totalComics: Int
    let pagesRead: Int
    let favorites: Int
    let inProgress: Int
    let finished: Int
    let unread: Int
    let runsCount: Int
    let readingStreak: Int
    let activityMap: [String: Int]
    let publisherBreakdown: [PublisherStat]
    let topSeries: [SeriesStat]
    let recentlyRead: [Comic]

    static func load() -> LibraryStats {
        let db = DatabaseManager.shared
        let total     = db.scalarInt("SELECT COUNT(*) FROM comics WHERE deleted_at IS NULL")
        let pagesRead = db.scalarInt("""
            SELECT COALESCE(SUM(rp.current_page), 0) FROM reading_progress rp
            JOIN comics c ON rp.comic_id = c.id WHERE c.deleted_at IS NULL
        """)
        let favorites = db.scalarInt("SELECT COUNT(*) FROM comics WHERE is_favorite = 1 AND deleted_at IS NULL")
        let inProg    = db.scalarInt("""
            SELECT COUNT(*) FROM comics c
            JOIN reading_progress rp ON c.id = rp.comic_id
            WHERE rp.current_page > 0
              AND (c.page_count = 0 OR rp.current_page < c.page_count - 2)
              AND c.deleted_at IS NULL
        """)
        let finished  = db.scalarInt("""
            SELECT COUNT(*) FROM comics c
            JOIN reading_progress rp ON c.id = rp.comic_id
            WHERE c.page_count > 1 AND rp.current_page >= c.page_count - 2
              AND c.deleted_at IS NULL
        """)
        let runsCount = db.scalarInt("SELECT COUNT(*) FROM runs")

        let streakDates = db.rows(
            "SELECT DISTINCT date(updated_at) FROM reading_progress ORDER BY date(updated_at) DESC"
        ) { stmt in db.colText(stmt, 0) ?? "" }
        let streak = computeStreak(dates: streakDates)

        let activityMap = db.readingActivityMap(days: 126)

        let pubRows = db.rows("""
            SELECT publisher, COUNT(*) as cnt FROM comics
            WHERE deleted_at IS NULL GROUP BY publisher ORDER BY cnt DESC
        """) { stmt in
            PublisherStat(publisher: db.colText(stmt, 0) ?? "", count: Int(sqlite3_column_int(stmt, 1)))
        }

        let seriesRows = db.rows("""
            SELECT series, publisher, COUNT(*) as cnt FROM comics
            WHERE deleted_at IS NULL
            GROUP BY publisher, series ORDER BY cnt DESC LIMIT 5
        """) { stmt in
            SeriesStat(series: db.colText(stmt, 0) ?? "", publisher: db.colText(stmt, 1) ?? "",
                       count: Int(sqlite3_column_int(stmt, 2)))
        }

        let recent = db.inProgress(limit: 8)

        return LibraryStats(
            totalComics: total, pagesRead: pagesRead, favorites: favorites,
            inProgress: inProg, finished: finished, unread: max(0, total - inProg - finished),
            runsCount: runsCount, readingStreak: streak, activityMap: activityMap,
            publisherBreakdown: pubRows, topSeries: seriesRows, recentlyRead: recent
        )
    }

    private static func computeStreak(dates: [String]) -> Int {
        guard !dates.isEmpty else { return 0 }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(identifier: "UTC")
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let yesterday = cal.date(byAdding: .day, value: -1, to: today) else { return 0 }
        var streak = 0
        var expected: Date? = nil
        for str in dates {
            guard let d = fmt.date(from: str) else { continue }
            let day = cal.startOfDay(for: d)
            if expected == nil {
                // Start streak from today or yesterday — allow for days where reading
                // happened before midnight in the user's timezone
                if day == today || day == yesterday {
                    streak = 1
                    expected = cal.date(byAdding: .day, value: -1, to: day)
                } else {
                    break
                }
            } else if day == expected {
                streak += 1
                expected = cal.date(byAdding: .day, value: -1, to: day)
            } else {
                break
            }
        }
        return streak
    }
}
