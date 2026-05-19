import sqlite3
import os
from config import get_data_dir

DB_PATH = os.path.join(get_data_dir(), 'comics.db')


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    return conn


def migrate_db():
    """Add new columns and tables to existing databases without losing data."""
    conn = get_db()
    for sql in [
        "ALTER TABLE runs ADD COLUMN rating INTEGER",
        "ALTER TABLE runs ADD COLUMN review TEXT",
        "ALTER TABLE runs ADD COLUMN buy_link TEXT",
        """CREATE TABLE IF NOT EXISTS favorites (
               comic_id INTEGER PRIMARY KEY REFERENCES comics(id) ON DELETE CASCADE
           )""",
        "CREATE INDEX IF NOT EXISTS idx_comics_publisher ON comics(publisher)",
        "CREATE INDEX IF NOT EXISTS idx_comics_series ON comics(series)",
        "CREATE INDEX IF NOT EXISTS idx_run_items_run_id ON run_items(run_id, position)",
        "CREATE INDEX IF NOT EXISTS idx_reading_progress ON reading_progress(comic_id)",
        """CREATE TABLE IF NOT EXISTS tags (
               id   INTEGER PRIMARY KEY AUTOINCREMENT,
               name TEXT UNIQUE NOT NULL
           )""",
        """CREATE TABLE IF NOT EXISTS comic_tags (
               comic_id INTEGER REFERENCES comics(id) ON DELETE CASCADE,
               tag_id   INTEGER REFERENCES tags(id)   ON DELETE CASCADE,
               PRIMARY KEY (comic_id, tag_id)
           )""",
        "CREATE INDEX IF NOT EXISTS idx_comic_tags_comic ON comic_tags(comic_id)",
        "ALTER TABLE comics ADD COLUMN character TEXT",
        "ALTER TABLE comics ADD COLUMN position INTEGER",
        "ALTER TABLE comics ADD COLUMN writer TEXT",
        "ALTER TABLE comics ADD COLUMN penciller TEXT",
        "ALTER TABLE comics ADD COLUMN year INTEGER",
        "ALTER TABLE comics ADD COLUMN story_arc TEXT",
        "ALTER TABLE comics ADD COLUMN language_iso TEXT",
        """CREATE TABLE IF NOT EXISTS reading_list (
               comic_id INTEGER PRIMARY KEY REFERENCES comics(id) ON DELETE CASCADE,
               added_at  TIMESTAMP DEFAULT CURRENT_TIMESTAMP
           )""",
        "CREATE INDEX IF NOT EXISTS idx_reading_list ON reading_list(comic_id)",
        """CREATE TABLE IF NOT EXISTS series_meta (
               publisher       TEXT NOT NULL,
               series          TEXT NOT NULL,
               description     TEXT DEFAULT '',
               custom_cover_id INTEGER REFERENCES comics(id) ON DELETE SET NULL,
               PRIMARY KEY (publisher, series)
           )""",
    ]:
        try:
            conn.execute(sql)
        except sqlite3.OperationalError:
            pass
    conn.execute("UPDATE comics SET position = id WHERE position IS NULL")
    conn.commit()
    conn.close()


def init_db():
    conn = get_db()
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS comics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            file_path TEXT UNIQUE NOT NULL,
            publisher TEXT,
            character TEXT,
            series TEXT,
            issue_number TEXT,
            page_count INTEGER DEFAULT 0,
            added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            position INTEGER,
            writer TEXT,
            penciller TEXT,
            year INTEGER,
            story_arc TEXT,
            language_iso TEXT
        );

        CREATE TABLE IF NOT EXISTS runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            description TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS run_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            run_id INTEGER REFERENCES runs(id) ON DELETE CASCADE,
            comic_id INTEGER REFERENCES comics(id) ON DELETE CASCADE,
            position INTEGER NOT NULL,
            notes TEXT,
            UNIQUE(run_id, comic_id)
        );

        CREATE TABLE IF NOT EXISTS reading_progress (
            comic_id INTEGER PRIMARY KEY REFERENCES comics(id),
            current_page INTEGER DEFAULT 0,
            last_read TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS ratings (
            comic_id INTEGER PRIMARY KEY REFERENCES comics(id),
            rating INTEGER CHECK(rating BETWEEN 1 AND 5),
            review TEXT
        );
    """)
    conn.commit()
    conn.close()
