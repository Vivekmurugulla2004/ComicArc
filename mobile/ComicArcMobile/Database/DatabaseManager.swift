import Foundation
import SQLite3

// SQLITE_TRANSIENT tells SQLite to copy the string — required in Swift
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DatabaseManager {
    static let shared = DatabaseManager()
    private var db: OpaquePointer?

    private init() {
        openDatabase()
        migrate()
    }

    // MARK: - Setup

    private func dbURL() -> URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ComicArc")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("comics.db")
    }

    private func openDatabase() {
        guard sqlite3_open(dbURL().path, &db) == SQLITE_OK else {
            print("[DB] open failed")
            return
        }
        exec("PRAGMA foreign_keys = ON")
        exec("PRAGMA journal_mode = WAL")
    }

    private func migrate() {
        exec("""
        CREATE TABLE IF NOT EXISTS comics (
            id            INTEGER PRIMARY KEY AUTOINCREMENT,
            title         TEXT NOT NULL,
            file_path     TEXT NOT NULL UNIQUE,
            publisher     TEXT DEFAULT 'Unknown',
            character     TEXT,
            series        TEXT DEFAULT 'General',
            issue_number  TEXT,
            page_count    INTEGER DEFAULT 0,
            rating        INTEGER DEFAULT 0,
            is_favorite   INTEGER DEFAULT 0,
            in_reading_list INTEGER DEFAULT 0,
            tags          TEXT DEFAULT '',
            date_added    TEXT DEFAULT (datetime('now')),
            sort_order    INTEGER DEFAULT 0
        )
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS reading_progress (
            comic_id    INTEGER PRIMARY KEY REFERENCES comics(id) ON DELETE CASCADE,
            current_page INTEGER DEFAULT 0,
            updated_at  TEXT DEFAULT (datetime('now'))
        )
        """)
    }

    // MARK: - Query: Comics

    func allComics(publisher: String? = nil,
                   character: String? = nil,
                   series: String? = nil,
                   search: String? = nil,
                   favoritesOnly: Bool = false,
                   readingListOnly: Bool = false) -> [Comic] {
        var conds = ["1=1"]
        var args: [String] = []

        if let pub = publisher, pub != "All" { conds.append("c.publisher = ?");   args.append(pub) }
        if let chr = character               { conds.append("c.character = ?");   args.append(chr) }
        if let ser = series                  { conds.append("c.series = ?");      args.append(ser) }
        if let q = search, !q.isEmpty {
            conds.append("(c.title LIKE ? OR c.series LIKE ?)")
            args += ["%\(q)%", "%\(q)%"]
        }
        if favoritesOnly    { conds.append("c.is_favorite = 1") }
        if readingListOnly  { conds.append("c.in_reading_list = 1") }

        let sql = """
            SELECT c.id, c.title, c.file_path, c.publisher, c.character, c.series,
                   c.issue_number, c.page_count, c.rating, c.is_favorite, c.in_reading_list,
                   c.tags, c.date_added, COALESCE(rp.current_page, 0) as progress
            FROM comics c
            LEFT JOIN reading_progress rp ON c.id = rp.comic_id
            WHERE \(conds.joined(separator: " AND "))
            ORDER BY c.publisher, c.series, c.issue_number, c.title
        """
        return queryComics(sql, args: args)
    }

    func comic(id: Int64) -> Comic? {
        let sql = """
            SELECT c.id, c.title, c.file_path, c.publisher, c.character, c.series,
                   c.issue_number, c.page_count, c.rating, c.is_favorite, c.in_reading_list,
                   c.tags, c.date_added, COALESCE(rp.current_page, 0) as progress
            FROM comics c
            LEFT JOIN reading_progress rp ON c.id = rp.comic_id
            WHERE c.id = ?
        """
        return queryComics(sql, args: [String(id)]).first
    }

    func inProgress(limit: Int = 10) -> [Comic] {
        let sql = """
            SELECT c.id, c.title, c.file_path, c.publisher, c.character, c.series,
                   c.issue_number, c.page_count, c.rating, c.is_favorite, c.in_reading_list,
                   c.tags, c.date_added, rp.current_page as progress
            FROM comics c
            JOIN reading_progress rp ON c.id = rp.comic_id
            WHERE rp.current_page > 0 AND (c.page_count = 0 OR rp.current_page < c.page_count - 1)
            ORDER BY rp.updated_at DESC
            LIMIT ?
        """
        return queryComics(sql, args: [String(limit)])
    }

    func publishers() -> [String] {
        var out: [String] = []
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "SELECT DISTINCT publisher FROM comics ORDER BY publisher", -1, &stmt, nil) == SQLITE_OK {
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let s = colText(stmt, 0) { out.append(s) }
            }
        }
        sqlite3_finalize(stmt)
        return out
    }

    // MARK: - Query: Groups

    func characterGroups(publisher: String? = nil) -> [SeriesGroup] {
        var conds = ["1=1"]
        var args: [String] = []
        if let pub = publisher, pub != "All" { conds.append("c.publisher = ?"); args.append(pub) }
        let sql = """
            SELECT c.publisher,
                   COALESCE(c.character, c.series) as group_name,
                   c.character,
                   COUNT(*) as issue_count,
                   MIN(c.id) as cover_id,
                   SUM(CASE WHEN rp.current_page > 0 THEN 1 ELSE 0 END) as started,
                   SUM(CASE WHEN c.page_count > 0 AND rp.current_page >= c.page_count - 1 THEN 1 ELSE 0 END) as completed
            FROM comics c
            LEFT JOIN reading_progress rp ON c.id = rp.comic_id
            WHERE \(conds.joined(separator: " AND "))
            GROUP BY c.publisher, COALESCE(c.character, c.series)
            ORDER BY c.publisher, group_name
        """
        return queryGroups(sql, args: args)
    }

    func seriesGroups(character: String, publisher: String? = nil) -> [SeriesGroup] {
        var conds = ["c.character = ?"]
        var args = [character]
        if let pub = publisher, pub != "All" { conds.append("c.publisher = ?"); args.append(pub) }
        let sql = """
            SELECT c.publisher,
                   c.series as group_name,
                   c.character,
                   COUNT(*) as issue_count,
                   MIN(c.id) as cover_id,
                   SUM(CASE WHEN rp.current_page > 0 THEN 1 ELSE 0 END) as started,
                   SUM(CASE WHEN c.page_count > 0 AND rp.current_page >= c.page_count - 1 THEN 1 ELSE 0 END) as completed
            FROM comics c
            LEFT JOIN reading_progress rp ON c.id = rp.comic_id
            WHERE \(conds.joined(separator: " AND "))
            GROUP BY c.publisher, c.series
            ORDER BY c.series
        """
        return queryGroups(sql, args: args)
    }

    // MARK: - Mutations

    @discardableResult
    func insertComic(title: String, filePath: String, publisher: String,
                     character: String?, series: String, issueNumber: String?,
                     pageCount: Int) -> Int64? {
        let sql = """
            INSERT OR IGNORE INTO comics
              (title, file_path, publisher, character, series, issue_number, page_count)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, title,      -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, filePath,   -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, publisher,  -1, SQLITE_TRANSIENT)
        if let c = character { sqlite3_bind_text(stmt, 4, c, -1, SQLITE_TRANSIENT) }
        else                 { sqlite3_bind_null(stmt, 4) }
        sqlite3_bind_text(stmt, 5, series,     -1, SQLITE_TRANSIENT)
        if let n = issueNumber { sqlite3_bind_text(stmt, 6, n, -1, SQLITE_TRANSIENT) }
        else                   { sqlite3_bind_null(stmt, 6) }
        sqlite3_bind_int(stmt,  7, Int32(pageCount))
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        let rowid = sqlite3_last_insert_rowid(db)
        return rowid > 0 ? rowid : nil
    }

    func updateProgress(comicId: Int64, page: Int) {
        let sql = """
            INSERT INTO reading_progress (comic_id, current_page)
            VALUES (?, ?)
            ON CONFLICT(comic_id) DO UPDATE
              SET current_page = excluded.current_page,
                  updated_at   = datetime('now')
        """
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, comicId)
            sqlite3_bind_int(stmt,  2, Int32(page))
            sqlite3_step(stmt)
        }
        sqlite3_finalize(stmt)
    }

    func setFavorite(_ id: Int64, _ value: Bool) {
        exec("UPDATE comics SET is_favorite = \(value ? 1 : 0) WHERE id = \(id)")
    }

    func setRating(_ id: Int64, _ rating: Int) {
        exec("UPDATE comics SET rating = \(rating) WHERE id = \(id)")
    }

    func setInReadingList(_ id: Int64, _ value: Bool) {
        exec("UPDATE comics SET in_reading_list = \(value ? 1 : 0) WHERE id = \(id)")
    }

    func updatePageCount(_ id: Int64, _ count: Int) {
        exec("UPDATE comics SET page_count = \(count) WHERE id = \(id)")
    }

    func deleteComic(_ id: Int64) {
        exec("DELETE FROM comics WHERE id = \(id)")
    }

    // MARK: - Public helpers for ad-hoc queries (used by StatsView)

    func scalarInt(_ sql: String) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        let result = sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
        sqlite3_finalize(stmt)
        return result
    }

    func rows<T>(_ sql: String, map: (OpaquePointer?) -> T) -> [T] {
        var out: [T] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        while sqlite3_step(stmt) == SQLITE_ROW { out.append(map(stmt)) }
        sqlite3_finalize(stmt)
        return out
    }

    func colText(_ stmt: OpaquePointer?, _ col: Int32) -> String? {
        guard let p = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: p)
    }

    // MARK: - Private helpers

    private func exec(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func queryComics(_ sql: String, args: [String]) -> [Comic] {
        var out: [Comic] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        for (i, v) in args.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), v, -1, SQLITE_TRANSIENT)
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let tagsStr = colText(stmt, 11) ?? ""
            let tags = tagsStr.isEmpty ? [] : tagsStr.split(separator: ",").map(String.init)
            out.append(Comic(
                id: sqlite3_column_int64(stmt, 0),
                title:         colText(stmt, 1)  ?? "",
                filePath:      colText(stmt, 2)  ?? "",
                publisher:     colText(stmt, 3)  ?? "Unknown",
                character:     colText(stmt, 4),
                series:        colText(stmt, 5)  ?? "General",
                issueNumber:   colText(stmt, 6),
                pageCount:     Int(sqlite3_column_int(stmt, 7)),
                progress:      Int(sqlite3_column_int(stmt, 13)),
                rating:        Int(sqlite3_column_int(stmt, 8)),
                isFavorite:    sqlite3_column_int(stmt, 9)  != 0,
                inReadingList: sqlite3_column_int(stmt, 10) != 0,
                tags: tags,
                dateAdded: Date()
            ))
        }
        sqlite3_finalize(stmt)
        return out
    }

    private func queryGroups(_ sql: String, args: [String]) -> [SeriesGroup] {
        var out: [SeriesGroup] = []
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        for (i, v) in args.enumerated() {
            sqlite3_bind_text(stmt, Int32(i + 1), v, -1, SQLITE_TRANSIENT)
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(SeriesGroup(
                groupName:    colText(stmt, 1) ?? "",
                character:    colText(stmt, 2),
                publisher:    colText(stmt, 0) ?? "",
                coverComicId: sqlite3_column_int64(stmt, 4),
                issueCount:   Int(sqlite3_column_int(stmt, 3)),
                started:      Int(sqlite3_column_int(stmt, 5)),
                completed:    Int(sqlite3_column_int(stmt, 6))
            ))
        }
        sqlite3_finalize(stmt)
        return out
    }

}
