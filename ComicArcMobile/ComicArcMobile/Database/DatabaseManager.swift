import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class DatabaseManager {
    static let shared = DatabaseManager()

    private let queue = DispatchQueue(label: "com.comicarc.db", qos: .userInitiated)
    private var db: OpaquePointer?

    private(set) var isDatabaseAvailable = false

    private init() {
        openDatabase()
        migrate()
    }

    private func dbURL() -> URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ComicArc")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("comics.db")
    }

    private func openDatabase() {
        let result = sqlite3_open(dbURL().path, &db)
        guard result == SQLITE_OK else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            assertionFailure("DatabaseManager: sqlite3_open failed — \(msg)")
            db = nil
            return
        }
        isDatabaseAvailable = true
        exec("PRAGMA foreign_keys = ON")
        exec("PRAGMA journal_mode = WAL")
    }

    private func migrate() {
        exec("""
        CREATE TABLE IF NOT EXISTS comics (
            id                INTEGER PRIMARY KEY AUTOINCREMENT,
            title             TEXT NOT NULL,
            file_path         TEXT NOT NULL UNIQUE,
            publisher         TEXT DEFAULT 'Unknown',
            character         TEXT,
            series            TEXT DEFAULT 'General',
            issue_number      TEXT,
            page_count        INTEGER DEFAULT 0,
            rating            INTEGER DEFAULT 0,
            is_favorite       INTEGER DEFAULT 0,
            in_reading_list   INTEGER DEFAULT 0,
            date_added        TEXT DEFAULT (datetime('now')),
            sort_order        INTEGER DEFAULT 0
        )
        """)

        exec("ALTER TABLE comics ADD COLUMN writer            TEXT")
        exec("ALTER TABLE comics ADD COLUMN summary           TEXT")
        exec("ALTER TABLE comics ADD COLUMN custom_cover_path TEXT")

        exec("CREATE INDEX IF NOT EXISTS idx_comics_publisher    ON comics(publisher)")
        exec("CREATE INDEX IF NOT EXISTS idx_comics_character    ON comics(character)")
        exec("CREATE INDEX IF NOT EXISTS idx_comics_series       ON comics(series)")
        exec("CREATE INDEX IF NOT EXISTS idx_comics_title        ON comics(title)")
        exec("CREATE INDEX IF NOT EXISTS idx_comics_date_added   ON comics(date_added)")
        exec("CREATE INDEX IF NOT EXISTS idx_comics_is_favorite  ON comics(is_favorite)")
        exec("CREATE INDEX IF NOT EXISTS idx_comics_reading_list ON comics(in_reading_list)")
        exec("CREATE INDEX IF NOT EXISTS idx_comics_rating       ON comics(rating)")
        exec("""
        CREATE TABLE IF NOT EXISTS reading_progress (
            comic_id     INTEGER PRIMARY KEY REFERENCES comics(id) ON DELETE CASCADE,
            current_page INTEGER DEFAULT 0,
            updated_at   TEXT DEFAULT (datetime('now'))
        )
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_progress_updated ON reading_progress(updated_at)")
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
        exec("""
        CREATE TABLE IF NOT EXISTS collections (
            id         INTEGER PRIMARY KEY AUTOINCREMENT,
            name       TEXT NOT NULL UNIQUE,
            sort_order INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now'))
        )
        """)
        exec("""
        CREATE TABLE IF NOT EXISTS collection_items (
            collection_id INTEGER REFERENCES collections(id) ON DELETE CASCADE,
            comic_id      INTEGER REFERENCES comics(id)       ON DELETE CASCADE,
            sort_order    INTEGER DEFAULT 0,
            PRIMARY KEY (collection_id, comic_id)
        )
        """)
    }

    enum SortOrder: String, CaseIterable {
        case publisher = "Publisher"
        case title     = "Title"
        case dateAdded = "Date Added"
        case rating    = "Rating"
        case progress  = "Progress"
        case manual    = "Custom Order"

        var orderClause: String {
            switch self {
            case .publisher: return "c.publisher, c.series, c.issue_number, c.title"
            case .title:     return "c.title"
            case .dateAdded: return "c.date_added DESC"
            case .rating:    return "c.rating DESC, c.title"
            case .progress:  return "COALESCE(rp.current_page, 0) DESC, c.title"
            case .manual:    return "c.sort_order, c.issue_number, c.title"
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
        if let ser = series { conds.append("c.series = ?"); args.append(ser) }
        if let q = search, !q.isEmpty {
            conds.append("(c.title LIKE ? OR c.series LIKE ?)")
            args += ["%\(q)%", "%\(q)%"]
        }
        if favoritesOnly   { conds.append("c.is_favorite = 1") }
        if readingListOnly { conds.append("c.in_reading_list = 1") }

        let sql = """
            SELECT c.id, c.title, c.file_path, c.publisher, c.character, c.series,
                   c.issue_number, c.page_count, c.rating, c.is_favorite, c.in_reading_list,
                   '' as tags, c.date_added, COALESCE(rp.current_page, 0) as progress,
                   c.writer, c.summary, c.custom_cover_path
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
                   '' as tags, c.date_added, COALESCE(rp.current_page, 0) as progress,
                   c.writer, c.summary, c.custom_cover_path
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
                   '' as tags, c.date_added, rp.current_page as progress,
                   c.writer, c.summary, c.custom_cover_path
            FROM comics c
            JOIN reading_progress rp ON c.id = rp.comic_id
            WHERE rp.current_page > 0 AND (c.page_count = 0 OR rp.current_page < c.page_count - 1)
            ORDER BY rp.updated_at DESC
            LIMIT ?
        """
        return queryComics(sql, args: [String(limit)])
    }

    func publishers() -> [String] {
        queue.sync {
            var out: [String] = []
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT DISTINCT publisher FROM comics ORDER BY publisher",
                                  -1, &stmt, nil) == SQLITE_OK {
                while sqlite3_step(stmt) == SQLITE_ROW {
                    if let s = colText(stmt, 0) { out.append(s) }
                }
            }
            sqlite3_finalize(stmt)
            return out
        }
    }

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

    @discardableResult
    func insertComic(title: String, filePath: String, publisher: String,
                     character: String?, series: String, issueNumber: String?,
                     pageCount: Int, writer: String? = nil, summary: String? = nil) -> Int64? {
        queue.sync {
            let sql = """
                INSERT OR IGNORE INTO comics
                  (title, file_path, publisher, character, series, issue_number, page_count, writer, summary)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            sqlite3_bind_text(stmt, 1, title,     -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, filePath,  -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, publisher, -1, SQLITE_TRANSIENT)
            if let c = character   { sqlite3_bind_text(stmt, 4, c, -1, SQLITE_TRANSIENT) }
            else                   { sqlite3_bind_null(stmt, 4) }
            sqlite3_bind_text(stmt, 5, series, -1, SQLITE_TRANSIENT)
            if let n = issueNumber { sqlite3_bind_text(stmt, 6, n, -1, SQLITE_TRANSIENT) }
            else                   { sqlite3_bind_null(stmt, 6) }
            sqlite3_bind_int(stmt,  7, Int32(pageCount))
            if let w = writer  { sqlite3_bind_text(stmt, 8, w, -1, SQLITE_TRANSIENT) }
            else               { sqlite3_bind_null(stmt, 8) }
            if let s = summary { sqlite3_bind_text(stmt, 9, s, -1, SQLITE_TRANSIENT) }
            else               { sqlite3_bind_null(stmt, 9) }
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
            let rowid = sqlite3_last_insert_rowid(db)
            return rowid > 0 ? rowid : nil
        }
    }

    func updateProgress(comicId: Int64, page: Int) {
        queue.sync {
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
    }

    func setFavorite(_ id: Int64, _ value: Bool) {
        prepared("UPDATE comics SET is_favorite = ? WHERE id = ?") {
            sqlite3_bind_int($0, 1, value ? 1 : 0); sqlite3_bind_int64($0, 2, id)
        }
    }

    func setRating(_ id: Int64, _ rating: Int) {
        prepared("UPDATE comics SET rating = ? WHERE id = ?") {
            sqlite3_bind_int($0, 1, Int32(rating)); sqlite3_bind_int64($0, 2, id)
        }
    }

    func setInReadingList(_ id: Int64, _ value: Bool) {
        prepared("UPDATE comics SET in_reading_list = ? WHERE id = ?") {
            sqlite3_bind_int($0, 1, value ? 1 : 0); sqlite3_bind_int64($0, 2, id)
        }
    }

    func deleteComic(_ id: Int64) {
        prepared("DELETE FROM comics WHERE id = ?") { sqlite3_bind_int64($0, 1, id) }
    }

    @discardableResult
    func restoreComic(title: String, filePath: String, publisher: String, character: String?,
                      series: String, issueNumber: String?, pageCount: Int,
                      rating: Int, isFavorite: Bool, inReadingList: Bool) -> Int64? {
        queue.sync {
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
            if let c = character   { sqlite3_bind_text(stmt, 4, c, -1, SQLITE_TRANSIENT) }
            else                   { sqlite3_bind_null(stmt, 4) }
            sqlite3_bind_text(stmt, 5, series, -1, SQLITE_TRANSIENT)
            if let n = issueNumber { sqlite3_bind_text(stmt, 6, n, -1, SQLITE_TRANSIENT) }
            else                   { sqlite3_bind_null(stmt, 6) }
            sqlite3_bind_int(stmt,  7, Int32(pageCount))
            sqlite3_bind_int(stmt,  8, Int32(rating))
            sqlite3_bind_int(stmt,  9, isFavorite    ? 1 : 0)
            sqlite3_bind_int(stmt, 10, inReadingList ? 1 : 0)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
            let rowid = sqlite3_last_insert_rowid(db)
            if rowid > 0 { return rowid }

            var s2: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT id FROM comics WHERE file_path = ?",
                                     -1, &s2, nil) == SQLITE_OK else { return nil }
            sqlite3_bind_text(s2, 1, filePath, -1, SQLITE_TRANSIENT)
            let existing = sqlite3_step(s2) == SQLITE_ROW ? sqlite3_column_int64(s2, 0) : nil
            sqlite3_finalize(s2)
            return existing
        }
    }

    func comicId(forFilePath filePath: String) -> Int64? {
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT id FROM comics WHERE file_path = ?",
                                     -1, &stmt, nil) == SQLITE_OK else { return nil }
            sqlite3_bind_text(stmt, 1, filePath, -1, SQLITE_TRANSIENT)
            let result = sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : nil
            sqlite3_finalize(stmt)
            return result
        }
    }

    func updateMetadata(_ id: Int64, title: String, publisher: String, character: String?,
                        series: String, issueNumber: String?) {
        queue.sync {
            var stmt: OpaquePointer?
            let sql = "UPDATE comics SET title=?, publisher=?, character=?, series=?, issue_number=? WHERE id=?"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, title,     -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, publisher, -1, SQLITE_TRANSIENT)
            if let c = character   { sqlite3_bind_text(stmt, 3, c, -1, SQLITE_TRANSIENT) }
            else                   { sqlite3_bind_null(stmt, 3) }
            sqlite3_bind_text(stmt, 4, series, -1, SQLITE_TRANSIENT)
            if let n = issueNumber { sqlite3_bind_text(stmt, 5, n, -1, SQLITE_TRANSIENT) }
            else                   { sqlite3_bind_null(stmt, 5) }
            sqlite3_bind_int64(stmt, 6, id)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func tags(for comicId: Int64) -> [Tag] {
        queue.sync {
            let sql = """
                SELECT t.id, t.name FROM tags t
                JOIN comic_tags ct ON t.id = ct.tag_id
                WHERE ct.comic_id = ?
                ORDER BY t.name
            """
            var out: [Tag] = []
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            sqlite3_bind_int64(stmt, 1, comicId)
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(Tag(id: sqlite3_column_int64(stmt, 0),
                               name: colText(stmt, 1) ?? "",
                               comicCount: 0))
            }
            sqlite3_finalize(stmt)
            return out
        }
    }

    func setTags(for comicId: Int64, names: [String]) {
        queue.sync {
            exec("BEGIN")
            prepared_unsafe("DELETE FROM comic_tags WHERE comic_id = ?") {
                sqlite3_bind_int64($0, 1, comicId)
            }
            for name in names {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO tags (name) VALUES (?)",
                                      -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_text(stmt, 1, trimmed, -1, SQLITE_TRANSIENT)
                    sqlite3_step(stmt)
                }
                sqlite3_finalize(stmt)
                stmt = nil
                if sqlite3_prepare_v2(db,
                    "INSERT OR IGNORE INTO comic_tags (comic_id, tag_id) SELECT ?, id FROM tags WHERE name = ?",
                    -1, &stmt, nil) == SQLITE_OK {
                    sqlite3_bind_int64(stmt, 1, comicId)
                    sqlite3_bind_text(stmt, 2, trimmed, -1, SQLITE_TRANSIENT)
                    sqlite3_step(stmt)
                }
                sqlite3_finalize(stmt)
            }
            exec("COMMIT")
        }
    }

    func allTagsByComicId() -> [Int64: [String]] {
        queue.sync {
            var result: [Int64: [String]] = [:]
            var stmt: OpaquePointer?
            let sql = """
                SELECT ct.comic_id, t.name
                FROM comic_tags ct JOIN tags t ON ct.tag_id = t.id
                ORDER BY ct.comic_id, t.name
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return result }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id   = sqlite3_column_int64(stmt, 0)
                let name = colText(stmt, 1) ?? ""
                result[id, default: []].append(name)
            }
            sqlite3_finalize(stmt)
            return result
        }
    }

    func allRuns() -> [Run] {
        let sql = """
            SELECT r.id, r.title, r.description, r.created_at,
                   COUNT(ri.id) as item_count,
                   SUM(CASE WHEN c.page_count > 0 AND COALESCE(rp.current_page,0) >= c.page_count - 1
                            THEN 1 ELSE 0 END) as completed
            FROM runs r
            LEFT JOIN run_items ri ON r.id = ri.run_id
            LEFT JOIN comics c ON ri.comic_id = c.id
            LEFT JOIN reading_progress rp ON c.id = rp.comic_id
            GROUP BY r.id
            ORDER BY r.created_at DESC
        """
        return rows(sql) { mapRun(stmt: $0) }
    }

    func firstActiveRun() -> Run? {
        let sql = """
            SELECT r.id, r.title, r.description, r.created_at,
                   COUNT(ri.id) as item_count,
                   SUM(CASE WHEN c.page_count > 0 AND COALESCE(rp.current_page,0) >= c.page_count - 1
                            THEN 1 ELSE 0 END) as completed
            FROM runs r
            LEFT JOIN run_items ri ON r.id = ri.run_id
            LEFT JOIN comics c ON ri.comic_id = c.id
            LEFT JOIN reading_progress rp ON c.id = rp.comic_id
            GROUP BY r.id
            HAVING item_count > 0 AND completed > 0 AND completed < item_count
            ORDER BY r.created_at DESC
            LIMIT 1
        """
        return rows(sql) { mapRun(stmt: $0) }.first
    }

    private func mapRun(stmt: OpaquePointer?) -> Run {
        Run(
            id:             sqlite3_column_int64(stmt, 0),
            title:          colText(stmt, 1) ?? "",
            description:    colText(stmt, 2) ?? "",
            createdAt:      DatabaseManager.sqliteDateFormatter.date(from: colText(stmt, 3) ?? "") ?? Date(),
            itemCount:      Int(sqlite3_column_int(stmt, 4)),
            completedCount: Int(sqlite3_column_int(stmt, 5))
        )
    }

    func runItems(runId: Int64) -> [RunItem] {
        let sql = """
            SELECT ri.id, ri.run_id, ri.position, ri.notes,
                   c.id, c.title, c.file_path, c.publisher, c.character, c.series,
                   c.issue_number, c.page_count, c.rating, c.is_favorite, c.in_reading_list,
                   '' as tags, c.date_added, COALESCE(rp.current_page, 0) as progress,
                   c.writer, c.summary, c.custom_cover_path
            FROM run_items ri
            JOIN comics c ON ri.comic_id = c.id
            LEFT JOIN reading_progress rp ON c.id = rp.comic_id
            WHERE ri.run_id = ?
            ORDER BY ri.position
        """
        return queue.sync {
            var out: [RunItem] = []
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            sqlite3_bind_int64(stmt, 1, runId)
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(RunItem(
                    id:       sqlite3_column_int64(stmt, 0),
                    runId:    sqlite3_column_int64(stmt, 1),
                    comic:    mapComic(stmt: stmt, offset: 4),
                    position: Int(sqlite3_column_int(stmt, 2)),
                    notes:    colText(stmt, 3) ?? ""
                ))
            }
            sqlite3_finalize(stmt)
            return out
        }
    }

    @discardableResult
    func createRun(title: String, description: String = "") -> Int64? {
        queue.sync {
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
    }

    func updateRun(_ id: Int64, title: String, description: String) {
        prepared("UPDATE runs SET title=?, description=? WHERE id=?") {
            sqlite3_bind_text($0, 1, title,       -1, SQLITE_TRANSIENT)
            sqlite3_bind_text($0, 2, description, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64($0, 3, id)
        }
    }

    func deleteRun(_ id: Int64) {
        prepared("DELETE FROM runs WHERE id = ?") { sqlite3_bind_int64($0, 1, id) }
    }

    func deleteAllComics() { prepared("DELETE FROM comics")  { _ in } }
    func deleteAllRuns()   { prepared("DELETE FROM runs")    { _ in } }

    func pageCountsForIds(_ ids: [Int64]) -> [Int64: Int] {
        guard !ids.isEmpty else { return [:] }
        return queue.sync {
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            let sql = "SELECT id, page_count FROM comics WHERE id IN (\(placeholders))"
            var result: [Int64: Int] = [:]
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return result }
            for (i, id) in ids.enumerated() { sqlite3_bind_int64(stmt, Int32(i + 1), id) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                result[sqlite3_column_int64(stmt, 0)] = Int(sqlite3_column_int(stmt, 1))
            }
            sqlite3_finalize(stmt)
            return result
        }
    }

    func updateProgressBatch(_ items: [(comicId: Int64, page: Int)]) {
        guard !items.isEmpty else { return }
        queue.sync {
            exec("BEGIN")
            let sql = """
                INSERT INTO reading_progress (comic_id, current_page)
                VALUES (?, ?)
                ON CONFLICT(comic_id) DO UPDATE
                  SET current_page = excluded.current_page,
                      updated_at   = datetime('now')
            """
            for item in items {
                prepared_unsafe(sql) {
                    sqlite3_bind_int64($0, 1, item.comicId)
                    sqlite3_bind_int($0,  2, Int32(item.page))
                }
            }
            exec("COMMIT")
        }
    }

    func addToRun(runId: Int64, comicId: Int64) {
        queue.sync {
            var pos = 0
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db, "SELECT COALESCE(MAX(position), -1) + 1 FROM run_items WHERE run_id = ?",
                                  -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, runId)
                if sqlite3_step(stmt) == SQLITE_ROW { pos = Int(sqlite3_column_int(stmt, 0)) }
            }
            sqlite3_finalize(stmt)
            prepared_unsafe("INSERT OR IGNORE INTO run_items (run_id, comic_id, position) VALUES (?, ?, ?)") {
                sqlite3_bind_int64($0, 1, runId)
                sqlite3_bind_int64($0, 2, comicId)
                sqlite3_bind_int($0,  3, Int32(pos))
            }
        }
    }

    func removeFromRun(runId: Int64, comicId: Int64) {
        prepared("DELETE FROM run_items WHERE run_id = ? AND comic_id = ?") {
            sqlite3_bind_int64($0, 1, runId); sqlite3_bind_int64($0, 2, comicId)
        }
    }

    func reorderRunItems(runId: Int64, orderedItemIds: [Int64]) {
        queue.sync {
            exec("BEGIN")
            for (pos, itemId) in orderedItemIds.enumerated() {
                prepared_unsafe("UPDATE run_items SET position = ? WHERE id = ? AND run_id = ?") {
                    sqlite3_bind_int($0,  1, Int32(pos))
                    sqlite3_bind_int64($0, 2, itemId)
                    sqlite3_bind_int64($0, 3, runId)
                }
            }
            exec("COMMIT")
        }
    }

    func updateRunItemNotes(itemId: Int64, notes: String) {
        prepared("UPDATE run_items SET notes=? WHERE id=?") {
            sqlite3_bind_text($0,  1, notes, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64($0, 2, itemId)
        }
    }

    func isComicInRun(runId: Int64, comicId: Int64) -> Bool {
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM run_items WHERE run_id=? AND comic_id=?",
                                     -1, &stmt, nil) == SQLITE_OK else { return false }
            sqlite3_bind_int64(stmt, 1, runId)
            sqlite3_bind_int64(stmt, 2, comicId)
            let result = sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int(stmt, 0) > 0 : false
            sqlite3_finalize(stmt)
            return result
        }
    }

    func setFavoriteForIds(_ ids: [Int64], isFavorite: Bool) {
        guard !ids.isEmpty else { return }
        queue.sync {
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "UPDATE comics SET is_favorite = ? WHERE id IN (\(placeholders))",
                -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_int(stmt, 1, isFavorite ? 1 : 0)
            for (i, id) in ids.enumerated() { sqlite3_bind_int64(stmt, Int32(i + 2), id) }
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func setInReadingListForIds(_ ids: [Int64], inList: Bool) {
        guard !ids.isEmpty else { return }
        queue.sync {
            let placeholders = ids.map { _ in "?" }.joined(separator: ",")
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db,
                "UPDATE comics SET in_reading_list = ? WHERE id IN (\(placeholders))",
                -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_int(stmt, 1, inList ? 1 : 0)
            for (i, id) in ids.enumerated() { sqlite3_bind_int64(stmt, Int32(i + 2), id) }
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func runsContainingComic(comicId: Int64) -> Set<Int64> {
        queue.sync {
            var result = Set<Int64>()
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT run_id FROM run_items WHERE comic_id=?",
                                     -1, &stmt, nil) == SQLITE_OK else { return result }
            sqlite3_bind_int64(stmt, 1, comicId)
            while sqlite3_step(stmt) == SQLITE_ROW {
                result.insert(sqlite3_column_int64(stmt, 0))
            }
            sqlite3_finalize(stmt)
            return result
        }
    }

    static let sqliteDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    func scalarInt(_ sql: String) -> Int {
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
            let result = sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
            sqlite3_finalize(stmt)
            return result
        }
    }

    func rows<T>(_ sql: String, map: (OpaquePointer?) -> T) -> [T] {
        queue.sync {
            var out: [T] = []
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            while sqlite3_step(stmt) == SQLITE_ROW { out.append(map(stmt)) }
            sqlite3_finalize(stmt)
            return out
        }
    }

    func colText(_ stmt: OpaquePointer?, _ col: Int32) -> String? {
        guard let p = sqlite3_column_text(stmt, col) else { return nil }
        return String(cString: p)
    }

    private func exec(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func prepared_unsafe(_ sql: String, bind: (OpaquePointer?) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        bind(stmt)
        sqlite3_step(stmt)
        sqlite3_finalize(stmt)
    }

    private func prepared(_ sql: String, bind: (OpaquePointer?) -> Void) {
        queue.sync { prepared_unsafe(sql, bind: bind) }
    }

    private func mapComic(stmt: OpaquePointer?, offset: Int32) -> Comic {
        let tagsStr = colText(stmt, offset + 11) ?? ""
        let tags    = tagsStr.isEmpty ? [] : tagsStr.split(separator: ",").map(String.init)
        return Comic(
            id:               sqlite3_column_int64(stmt, offset + 0),
            title:            colText(stmt, offset + 1)  ?? "",
            filePath:         colText(stmt, offset + 2)  ?? "",
            publisher:        colText(stmt, offset + 3)  ?? "Unknown",
            character:        colText(stmt, offset + 4),
            series:           colText(stmt, offset + 5)  ?? "General",
            issueNumber:      colText(stmt, offset + 6),
            pageCount:        Int(sqlite3_column_int(stmt, offset + 7)),
            progress:         Int(sqlite3_column_int(stmt, offset + 13)),
            rating:           Int(sqlite3_column_int(stmt, offset + 8)),
            isFavorite:       sqlite3_column_int(stmt, offset + 9)  != 0,
            inReadingList:    sqlite3_column_int(stmt, offset + 10) != 0,
            tags:             tags,
            dateAdded:        DatabaseManager.sqliteDateFormatter.date(
                                  from: colText(stmt, offset + 12) ?? "") ?? Date(),
            writer:           colText(stmt, offset + 14),
            summary:          colText(stmt, offset + 15),
            customCoverPath:  colText(stmt, offset + 16)
        )
    }

    private func queryComics(_ sql: String, args: [String]) -> [Comic] {
        queue.sync {
            var out: [Comic] = []
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            for (i, v) in args.enumerated() {
                sqlite3_bind_text(stmt, Int32(i + 1), v, -1, SQLITE_TRANSIENT)
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append(mapComic(stmt: stmt, offset: 0))
            }
            sqlite3_finalize(stmt)
            return out
        }
    }

    func setCustomCoverPath(id: Int64, path: String?) {
        queue.sync {
            var stmt: OpaquePointer?
            let sql = "UPDATE comics SET custom_cover_path = ? WHERE id = ?"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            if let path { sqlite3_bind_text(stmt, 1, path, -1, SQLITE_TRANSIENT) }
            else        { sqlite3_bind_null(stmt, 1) }
            sqlite3_bind_int64(stmt, 2, id)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func updateSortOrders(_ items: [(id: Int64, sortOrder: Int)]) {
        guard !items.isEmpty else { return }
        queue.sync {
            exec("BEGIN")
            for item in items {
                prepared_unsafe("UPDATE comics SET sort_order = ? WHERE id = ?") {
                    sqlite3_bind_int($0,  1, Int32(item.sortOrder))
                    sqlite3_bind_int64($0, 2, item.id)
                }
            }
            exec("COMMIT")
        }
    }

    func renameSeries(from oldName: String, to newName: String, publisher: String? = nil) {
        queue.sync {
            var stmt: OpaquePointer?
            let sql: String
            if let pub = publisher {
                sql = "UPDATE comics SET series = ? WHERE series = ? AND publisher = ?"
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
                sqlite3_bind_text(stmt, 1, newName,  -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, oldName,  -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, pub,      -1, SQLITE_TRANSIENT)
            } else {
                sql = "UPDATE comics SET series = ? WHERE series = ?"
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
                sqlite3_bind_text(stmt, 1, newName, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, oldName, -1, SQLITE_TRANSIENT)
            }
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func mergeSeries(sources: [String], into target: String, publisher: String? = nil) {
        guard !sources.isEmpty else { return }
        queue.sync {
            exec("BEGIN")
            for source in sources where source != target {
                var stmt: OpaquePointer?
                if let pub = publisher {
                    let sql = "UPDATE comics SET series = ? WHERE series = ? AND publisher = ?"
                    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
                    sqlite3_bind_text(stmt, 1, target, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 2, source, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 3, pub,    -1, SQLITE_TRANSIENT)
                } else {
                    let sql = "UPDATE comics SET series = ? WHERE series = ?"
                    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { continue }
                    sqlite3_bind_text(stmt, 1, target, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(stmt, 2, source, -1, SQLITE_TRANSIENT)
                }
                sqlite3_step(stmt)
                sqlite3_finalize(stmt)
            }
            exec("COMMIT")
        }
    }

    func allDistinctSeries(publisher: String? = nil) -> [String] {
        queue.sync {
            var out: [String] = []
            var stmt: OpaquePointer?
            if let pub = publisher {
                let sql = "SELECT DISTINCT series FROM comics WHERE publisher = ? AND series != 'General' ORDER BY series"
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
                sqlite3_bind_text(stmt, 1, pub, -1, SQLITE_TRANSIENT)
            } else {
                let sql = "SELECT DISTINCT series FROM comics WHERE series != 'General' ORDER BY series"
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let s = colText(stmt, 0) { out.append(s) }
            }
            sqlite3_finalize(stmt)
            return out
        }
    }

    func allCollections() -> [Collection] {
        let sql = """
            SELECT c.id, c.name, COUNT(ci.comic_id) as cnt
            FROM collections c
            LEFT JOIN collection_items ci ON c.id = ci.collection_id
            GROUP BY c.id
            ORDER BY c.sort_order, c.name
        """
        return rows(sql) { stmt in
            Collection(id: sqlite3_column_int64(stmt, 0),
                       name: colText(stmt, 1) ?? "",
                       comicCount: Int(sqlite3_column_int(stmt, 2)))
        }
    }

    @discardableResult
    func createCollection(name: String) -> Int64? {
        queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "INSERT OR IGNORE INTO collections (name) VALUES (?)",
                                     -1, &stmt, nil) == SQLITE_OK else { return nil }
            sqlite3_bind_text(stmt, 1, name, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
            let id = sqlite3_last_insert_rowid(db)
            return id > 0 ? id : nil
        }
    }

    func renameCollection(id: Int64, name: String) {
        prepared("UPDATE collections SET name = ? WHERE id = ?") {
            sqlite3_bind_text($0, 1, name, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64($0, 2, id)
        }
    }

    func deleteCollection(_ id: Int64) {
        prepared("DELETE FROM collections WHERE id = ?") { sqlite3_bind_int64($0, 1, id) }
    }

    func addToCollection(collectionId: Int64, comicId: Int64) {
        queue.sync {
            var pos = 0
            var stmt: OpaquePointer?
            if sqlite3_prepare_v2(db,
                "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM collection_items WHERE collection_id = ?",
                -1, &stmt, nil) == SQLITE_OK {
                sqlite3_bind_int64(stmt, 1, collectionId)
                if sqlite3_step(stmt) == SQLITE_ROW { pos = Int(sqlite3_column_int(stmt, 0)) }
            }
            sqlite3_finalize(stmt)
            prepared_unsafe("INSERT OR IGNORE INTO collection_items (collection_id, comic_id, sort_order) VALUES (?, ?, ?)") {
                sqlite3_bind_int64($0, 1, collectionId)
                sqlite3_bind_int64($0, 2, comicId)
                sqlite3_bind_int($0,  3, Int32(pos))
            }
        }
    }

    func removeFromCollection(collectionId: Int64, comicId: Int64) {
        prepared("DELETE FROM collection_items WHERE collection_id = ? AND comic_id = ?") {
            sqlite3_bind_int64($0, 1, collectionId)
            sqlite3_bind_int64($0, 2, comicId)
        }
    }

    func comics(inCollection collectionId: Int64) -> [Comic] {
        let sql = """
            SELECT c.id, c.title, c.file_path, c.publisher, c.character, c.series,
                   c.issue_number, c.page_count, c.rating, c.is_favorite, c.in_reading_list,
                   '' as tags, c.date_added, COALESCE(rp.current_page, 0) as progress,
                   c.writer, c.summary, c.custom_cover_path
            FROM comics c
            JOIN collection_items ci ON c.id = ci.comic_id
            LEFT JOIN reading_progress rp ON c.id = rp.comic_id
            WHERE ci.collection_id = ?
            ORDER BY ci.sort_order, c.title
        """
        return queue.sync {
            var out: [Comic] = []
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            sqlite3_bind_int64(stmt, 1, collectionId)
            while sqlite3_step(stmt) == SQLITE_ROW { out.append(mapComic(stmt: stmt, offset: 0)) }
            sqlite3_finalize(stmt)
            return out
        }
    }

    func collectionsContainingComic(comicId: Int64) -> Set<Int64> {
        queue.sync {
            var result = Set<Int64>()
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT collection_id FROM collection_items WHERE comic_id = ?",
                                     -1, &stmt, nil) == SQLITE_OK else { return result }
            sqlite3_bind_int64(stmt, 1, comicId)
            while sqlite3_step(stmt) == SQLITE_ROW { result.insert(sqlite3_column_int64(stmt, 0)) }
            sqlite3_finalize(stmt)
            return result
        }
    }

    private func queryGroups(_ sql: String, args: [String]) -> [SeriesGroup] {
        queue.sync {
            var out: [SeriesGroup] = []
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            for (i, v) in args.enumerated() {
                sqlite3_bind_text(stmt, Int32(i + 1), v, -1, SQLITE_TRANSIENT)
            }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let pub = colText(stmt, 0) ?? ""
                let name = colText(stmt, 1) ?? ""
                out.append(SeriesGroup(
                    id:           "\(pub)|\(name)",
                    groupName:    name,
                    character:    colText(stmt, 2),
                    publisher:    pub,
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
}
