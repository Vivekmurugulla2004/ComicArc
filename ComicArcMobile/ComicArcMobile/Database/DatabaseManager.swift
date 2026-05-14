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
            return
        }
        exec("PRAGMA foreign_keys = ON")
        exec("PRAGMA journal_mode = WAL")
    }

    private func migrate() {
        exec("""
        CREATE TABLE IF NOT EXISTS comics (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            title           TEXT NOT NULL,
            file_path       TEXT NOT NULL UNIQUE,
            publisher       TEXT DEFAULT 'Unknown',
            character       TEXT,
            series          TEXT DEFAULT 'General',
            issue_number    TEXT,
            page_count      INTEGER DEFAULT 0,
            rating          INTEGER DEFAULT 0,
            is_favorite     INTEGER DEFAULT 0,
            in_reading_list INTEGER DEFAULT 0,
            date_added      TEXT DEFAULT (datetime('now')),
            sort_order      INTEGER DEFAULT 0
        )
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS reading_progress (
            comic_id     INTEGER PRIMARY KEY REFERENCES comics(id) ON DELETE CASCADE,
            current_page INTEGER DEFAULT 0,
            updated_at   TEXT DEFAULT (datetime('now'))
        )
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS tags (
            id   INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL
        )
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS comic_tags (
            comic_id INTEGER REFERENCES comics(id) ON DELETE CASCADE,
            tag_id   INTEGER REFERENCES tags(id)   ON DELETE CASCADE,
            PRIMARY KEY (comic_id, tag_id)
        )
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS runs (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            title       TEXT NOT NULL,
            description TEXT DEFAULT '',
            created_at  TEXT DEFAULT (datetime('now'))
        )
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS run_items (
            id       INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id   INTEGER REFERENCES runs(id)   ON DELETE CASCADE,
            comic_id INTEGER REFERENCES comics(id) ON DELETE CASCADE,
            position INTEGER NOT NULL,
            notes    TEXT DEFAULT '',
            UNIQUE(run_id, comic_id)
        )
        """)
    }

    // MARK: - Query: Comics

    enum SortOrder: String, CaseIterable {
        case publisher = "Publisher"
        case title     = "Title"
        case dateAdded = "Date Added"
        case rating    = "Rating"
        case progress  = "Progress"

        var orderClause: String {
            switch self {
            case .publisher: return "c.publisher, c.series, c.issue_number, c.title"
            case .title:     return "c.title"
            case .dateAdded: return "c.date_added DESC"
            case .rating:    return "c.rating DESC, c.title"
            case .progress:  return "COALESCE(rp.current_page, 0) DESC, c.title"
            }
        }
    }

    func allComics(publisher: String? = nil,
                   character: String? = nil,
                   series: String? = nil,
                   search: String? = nil,
                   favoritesOnly: Bool = false,
                   readingListOnly: Bool = false,
                   nullCharacterOnly: Bool = false,
                   sortOrder: SortOrder = .publisher) -> [Comic] {
        var conds = ["1=1"]
        var args: [String] = []

        if let pub = publisher, pub != "All" { conds.append("c.publisher = ?"); args.append(pub) }
        if nullCharacterOnly {
            conds.append("c.character IS NULL")
        } else if let chr = character {
            conds.append("c.character = ?")
            args.append(chr)
        }
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
                   '' as tags, c.date_added, COALESCE(rp.current_page, 0) as progress
            FROM comics c
            LEFT JOIN reading_progress rp ON c.id = rp.comic_id
            WHERE \(conds.joined(separator: " AND "))
            ORDER BY \(sortOrder.orderClause)
        """
        return queryComics(sql, args: args)
    }

    func comic(id: Int64) -> Comic? {
        let sql = """
            SELECT c.id, c.title, c.file_path, c.publisher, c.character, c.series,
                   c.issue_number, c.page_count, c.rating, c.is_favorite, c.in_reading_list,
                   '' as tags, c.date_added, COALESCE(rp.current_page, 0) as progress
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
                   '' as tags, c.date_added, rp.current_page as progress
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

    func deleteComic(_ id: Int64) {
        exec("DELETE FROM comics WHERE id = \(id)")
    }

    /// Upserts a comic record for backup restore.
    /// On conflict (same file_path) preserves existing title/series/publisher from the DB
    /// but restores ratings, favorites, reading list, and page count.
    @discardableResult
    func restoreComic(title: String, filePath: String, publisher: String, character: String?,
                      series: String, issueNumber: String?, pageCount: Int,
                      rating: Int, isFavorite: Bool, inReadingList: Bool) -> Int64? {
        let sql = """
            INSERT INTO comics
              (title, file_path, publisher, character, series, issue_number, page_count, rating, is_favorite, in_reading_list)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(file_path) DO UPDATE SET
              rating          = MAX(excluded.rating,          comics.rating),
              is_favorite     = MAX(excluded.is_favorite,     comics.is_favorite),
              in_reading_list = MAX(excluded.in_reading_list, comics.in_reading_list),
              page_count      = CASE WHEN excluded.page_count > 0 THEN excluded.page_count ELSE comics.page_count END
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, title,     -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, filePath,  -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, publisher, -1, SQLITE_TRANSIENT)
        if let c = character { sqlite3_bind_text(stmt, 4, c, -1, SQLITE_TRANSIENT) }
        else                 { sqlite3_bind_null(stmt, 4) }
        sqlite3_bind_text(stmt, 5, series, -1, SQLITE_TRANSIENT)
        if let n = issueNumber { sqlite3_bind_text(stmt, 6, n, -1, SQLITE_TRANSIENT) }
        else                   { sqlite3_bind_null(stmt, 6) }
        sqlite3_bind_int(stmt,  7, Int32(pageCount))
        sqlite3_bind_int(stmt,  8, Int32(rating))
        sqlite3_bind_int(stmt,  9, isFavorite    ? 1 : 0)
        sqlite3_bind_int(stmt, 10, inReadingList ? 1 : 0)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        // sqlite3_last_insert_rowid returns the rowid of the upserted row
        let rowid = sqlite3_last_insert_rowid(db)
        if rowid > 0 { return rowid }
        // Fallback: look up by file path (handles the DO UPDATE path on some SQLite builds)
        return comicId(forFilePath: filePath)
    }

    func comicId(forFilePath filePath: String) -> Int64? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT id FROM comics WHERE file_path = ?",
                                 -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, filePath, -1, SQLITE_TRANSIENT)
        let result = sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : nil
        sqlite3_finalize(stmt)
        return result
    }

    func updateMetadata(_ id: Int64, title: String, publisher: String, character: String?,
                        series: String, issueNumber: String?) {
        var stmt: OpaquePointer?
        let sql = """
            UPDATE comics SET title=?, publisher=?, character=?, series=?, issue_number=?
            WHERE id=\(id)
        """
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, title,     -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, publisher, -1, SQLITE_TRANSIENT)
        if let c = character { sqlite3_bind_text(stmt, 3, c, -1, SQLITE_TRANSIENT) }
        else                 { sqlite3_bind_null(stmt, 3) }
        sqlite3_bind_text(stmt, 4, series, -1, SQLITE_TRANSIENT)
        if let n = issueNumber { sqlite3_bind_text(stmt, 5, n, -1, SQLITE_TRANSIENT) }
        else                   { sqlite3_bind_null(stmt, 5) }
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    // MARK: - Tags

    func allTags() -> [Tag] {
        let sql = """
            SELECT t.id, t.name, COUNT(ct.comic_id) as cnt
            FROM tags t LEFT JOIN comic_tags ct ON t.id = ct.tag_id
            GROUP BY t.id ORDER BY cnt DESC, t.name
        """
        return rows(sql) { stmt in
            Tag(id: sqlite3_column_int64(stmt, 0),
                name: colText(stmt, 1) ?? "",
                comicCount: Int(sqlite3_column_int(stmt, 2)))
        }
    }

    func tags(for comicId: Int64) -> [Tag] {
        let sql = """
            SELECT t.id, t.name, 0 as cnt FROM tags t
            JOIN comic_tags ct ON t.id = ct.tag_id
            WHERE ct.comic_id = \(comicId)
            ORDER BY t.name
        """
        return rows(sql) { stmt in
            Tag(id: sqlite3_column_int64(stmt, 0), name: colText(stmt, 1) ?? "", comicCount: 0)
        }
    }

    func setTags(for comicId: Int64, names: [String]) {
        exec("DELETE FROM comic_tags WHERE comic_id = \(comicId)")
        for name in names {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            exec("INSERT OR IGNORE INTO tags (name) VALUES ('\(trimmed.replacingOccurrences(of: "'", with: "''"))')")
            exec("""
                INSERT OR IGNORE INTO comic_tags (comic_id, tag_id)
                SELECT \(comicId), id FROM tags WHERE name = '\(trimmed.replacingOccurrences(of: "'", with: "''"))'
            """)
        }
    }

    func comics(withTag tagName: String) -> [Comic] {
        let sql = """
            SELECT c.id, c.title, c.file_path, c.publisher, c.character, c.series,
                   c.issue_number, c.page_count, c.rating, c.is_favorite, c.in_reading_list,
                   '' as tags, c.date_added, COALESCE(rp.current_page, 0) as progress
            FROM comics c
            LEFT JOIN reading_progress rp ON c.id = rp.comic_id
            JOIN comic_tags ct ON c.id = ct.comic_id
            JOIN tags t ON ct.tag_id = t.id
            WHERE t.name = ?
            ORDER BY c.publisher, c.series, c.title
        """
        return queryComics(sql, args: [tagName])
    }

    // MARK: - Runs

    func allRuns() -> [Run] {
        let sql = """
            SELECT r.id, r.title, r.description, r.created_at,
                   COUNT(ri.id) as item_count,
                   SUM(CASE WHEN c.page_count > 0 AND COALESCE(rp.current_page,0) >= c.page_count - 1
                            THEN 1 ELSE 0 END) as completed,
                   MIN(CASE WHEN (c.page_count = 0 OR COALESCE(rp.current_page,0) < c.page_count - 1)
                            THEN c.id END) as first_unfinished
            FROM runs r
            LEFT JOIN run_items ri ON r.id = ri.run_id
            LEFT JOIN comics c ON ri.comic_id = c.id
            LEFT JOIN reading_progress rp ON c.id = rp.comic_id
            GROUP BY r.id
            ORDER BY r.created_at DESC
        """
        return rows(sql) { stmt in
            let firstId = sqlite3_column_type(stmt, 6) != SQLITE_NULL
                          ? sqlite3_column_int64(stmt, 6) : nil
            return Run(
                id: sqlite3_column_int64(stmt, 0),
                title: colText(stmt, 1) ?? "",
                description: colText(stmt, 2) ?? "",
                createdAt: Date(),
                itemCount: Int(sqlite3_column_int(stmt, 4)),
                completedCount: Int(sqlite3_column_int(stmt, 5)),
                firstUnfinishedComicId: firstId
            )
        }
    }

    func runItems(runId: Int64) -> [RunItem] {
        let sql = """
            SELECT ri.id, ri.run_id, ri.position, ri.notes,
                   c.id, c.title, c.file_path, c.publisher, c.character, c.series,
                   c.issue_number, c.page_count, c.rating, c.is_favorite, c.in_reading_list,
                   c.date_added, COALESCE(rp.current_page, 0) as progress
            FROM run_items ri
            JOIN comics c ON ri.comic_id = c.id
            LEFT JOIN reading_progress rp ON c.id = rp.comic_id
            WHERE ri.run_id = \(runId)
            ORDER BY ri.position
        """
        return rows(sql) { stmt in
            let comic = Comic(
                id:            sqlite3_column_int64(stmt, 4),
                title:         colText(stmt, 5)  ?? "",
                filePath:      colText(stmt, 6)  ?? "",
                publisher:     colText(stmt, 7)  ?? "Unknown",
                character:     colText(stmt, 8),
                series:        colText(stmt, 9)  ?? "General",
                issueNumber:   colText(stmt, 10),
                pageCount:     Int(sqlite3_column_int(stmt, 11)),
                progress:      Int(sqlite3_column_int(stmt, 16)),
                rating:        Int(sqlite3_column_int(stmt, 12)),
                isFavorite:    sqlite3_column_int(stmt, 13) != 0,
                inReadingList: sqlite3_column_int(stmt, 14) != 0,
                tags: [],
                dateAdded: DatabaseManager.sqliteDateFormatter.date(from: colText(stmt, 15) ?? "") ?? Date()
            )
            return RunItem(
                id:       sqlite3_column_int64(stmt, 0),
                runId:    sqlite3_column_int64(stmt, 1),
                comic:    comic,
                position: Int(sqlite3_column_int(stmt, 2)),
                notes:    colText(stmt, 3) ?? ""
            )
        }
    }

    @discardableResult
    func createRun(title: String, description: String = "") -> Int64? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "INSERT INTO runs (title, description) VALUES (?, ?)",
                                 -1, &stmt, nil) == SQLITE_OK else { return nil }
        sqlite3_bind_text(stmt, 1, title,       -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, description, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        let id = sqlite3_last_insert_rowid(db)
        return id > 0 ? id : nil
    }

    func updateRun(_ id: Int64, title: String, description: String) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE runs SET title=?, description=? WHERE id=\(id)",
                                 -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, title,       -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, description, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    func deleteRun(_ id: Int64) {
        exec("DELETE FROM runs WHERE id = \(id)")
    }

    func addToRun(runId: Int64, comicId: Int64) {
        let pos = scalarInt("SELECT COALESCE(MAX(position), -1) + 1 FROM run_items WHERE run_id = \(runId)")
        exec("INSERT OR IGNORE INTO run_items (run_id, comic_id, position) VALUES (\(runId), \(comicId), \(pos))")
    }

    func removeFromRun(runId: Int64, comicId: Int64) {
        exec("DELETE FROM run_items WHERE run_id = \(runId) AND comic_id = \(comicId)")
    }

    func reorderRunItems(runId: Int64, orderedItemIds: [Int64]) {
        for (pos, itemId) in orderedItemIds.enumerated() {
            exec("UPDATE run_items SET position = \(pos) WHERE id = \(itemId) AND run_id = \(runId)")
        }
    }

    func updateRunItemNotes(itemId: Int64, notes: String) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "UPDATE run_items SET notes=? WHERE id=\(itemId)",
                                 -1, &stmt, nil) == SQLITE_OK else { return }
        sqlite3_bind_text(stmt, 1, notes, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    func isComicInRun(runId: Int64, comicId: Int64) -> Bool {
        scalarInt("SELECT COUNT(*) FROM run_items WHERE run_id=\(runId) AND comic_id=\(comicId)") > 0
    }

    // MARK: - Date parsing

    static let sqliteDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

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
                dateAdded: DatabaseManager.sqliteDateFormatter.date(from: colText(stmt, 12) ?? "") ?? Date()
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
