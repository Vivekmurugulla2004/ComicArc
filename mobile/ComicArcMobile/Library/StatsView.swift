import SwiftUI

struct StatsView: View {
    @EnvironmentObject var library: LibraryViewModel
    @State private var stats: LibraryStats?

    var body: some View {
        NavigationStack {
            Group {
                if let s = stats {
                    List {
                        // Summary cards
                        Section {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                statTile("Comics", value: "\(s.totalComics)", icon: "books.vertical", color: .orange)
                                statTile("Pages Read", value: "\(s.pagesRead)", icon: "doc.text", color: .blue)
                                statTile("Favorites", value: "\(s.favorites)", icon: "heart.fill", color: .red)
                                statTile("In Progress", value: "\(s.inProgress)", icon: "clock", color: .purple)
                            }
                            .listRowInsets(.init())
                            .listRowBackground(Color.clear)
                        }

                        // Completion breakdown
                        Section("Reading Status") {
                            completionRow("Finished", count: s.finished, total: s.totalComics, color: .green)
                            completionRow("In Progress", count: s.inProgress, total: s.totalComics, color: .orange)
                            completionRow("Unread", count: s.unread, total: s.totalComics, color: .secondary)
                        }

                        // Publisher breakdown
                        if !s.publisherBreakdown.isEmpty {
                            Section("By Publisher") {
                                ForEach(s.publisherBreakdown, id: \.publisher) { row in
                                    publisherRow(row, total: s.totalComics)
                                }
                            }
                        }

                        // Top series
                        if !s.topSeries.isEmpty {
                            Section("Top Series by Issue Count") {
                                ForEach(Array(s.topSeries.enumerated()), id: \.offset) { i, row in
                                    HStack {
                                        Text("\(i + 1)")
                                            .font(.caption).foregroundStyle(.secondary)
                                            .frame(width: 20, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(row.series)
                                                .font(.subheadline)
                                            Text(row.publisher)
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text("\(row.count)")
                                            .font(.subheadline.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        // Recently read
                        if !s.recentlyRead.isEmpty {
                            Section("Recently Read") {
                                ForEach(s.recentlyRead) { comic in
                                    HStack(spacing: 12) {
                                        CoverImage(comicId: comic.id)
                                            .frame(width: 36, height: 52)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(comic.title)
                                                .font(.subheadline)
                                                .lineLimit(1)
                                            if comic.pageCount > 0 {
                                                Text("p. \(comic.progress) / \(comic.pageCount)")
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if comic.isFinished {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
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
            .onAppear { stats = LibraryStats.load() }
            .refreshable { stats = LibraryStats.load() }
        }
    }

    // MARK: - Subviews

    private func statTile(_ label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func completionRow(_ label: String, count: Int, total: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(count)")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule()
                        .fill(color)
                        .frame(width: total > 0 ? geo.size.width * CGFloat(count) / CGFloat(total) : 0)
                }
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
                Text("\(row.count)")
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5))
                    Capsule()
                        .fill(Color.orange)
                        .frame(width: total > 0 ? geo.size.width * CGFloat(row.count) / CGFloat(total) : 0)
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Stats model

struct PublisherStat { let publisher: String; let count: Int }
struct SeriesStat     { let series: String; let publisher: String; let count: Int }

struct LibraryStats {
    let totalComics: Int
    let pagesRead: Int
    let favorites: Int
    let inProgress: Int
    let finished: Int
    let unread: Int
    let publisherBreakdown: [PublisherStat]
    let topSeries: [SeriesStat]
    let recentlyRead: [Comic]

    static func load() -> LibraryStats {
        let db = DatabaseManager.shared
        let total    = db.scalarInt("SELECT COUNT(*) FROM comics")
        let pagesRead = db.scalarInt("SELECT COALESCE(SUM(current_page), 0) FROM reading_progress")
        let favorites = db.scalarInt("SELECT COUNT(*) FROM comics WHERE is_favorite = 1")
        let inProg   = db.scalarInt("""
            SELECT COUNT(*) FROM comics c
            JOIN reading_progress rp ON c.id = rp.comic_id
            WHERE rp.current_page > 0 AND (c.page_count = 0 OR rp.current_page < c.page_count - 1)
        """)
        let finished = db.scalarInt("""
            SELECT COUNT(*) FROM comics c
            JOIN reading_progress rp ON c.id = rp.comic_id
            WHERE c.page_count > 0 AND rp.current_page >= c.page_count - 1
        """)

        let pubRows = db.rows("SELECT publisher, COUNT(*) as cnt FROM comics GROUP BY publisher ORDER BY cnt DESC") { stmt in
            PublisherStat(publisher: db.colText(stmt, 0) ?? "", count: Int(sqlite3_column_int(stmt, 1)))
        }

        let seriesRows = db.rows("""
            SELECT series, publisher, COUNT(*) as cnt FROM comics
            GROUP BY publisher, series ORDER BY cnt DESC LIMIT 5
        """) { stmt in
            SeriesStat(series: db.colText(stmt, 0) ?? "", publisher: db.colText(stmt, 1) ?? "", count: Int(sqlite3_column_int(stmt, 2)))
        }

        let recent = db.inProgress(limit: 8)

        return LibraryStats(
            totalComics: total, pagesRead: pagesRead, favorites: favorites,
            inProgress: inProg, finished: finished, unread: max(0, total - inProg - finished),
            publisherBreakdown: pubRows, topSeries: seriesRows, recentlyRead: recent
        )
    }
}
