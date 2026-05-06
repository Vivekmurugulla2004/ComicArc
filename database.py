import sqlite3
import os

DB_PATH = os.path.join(os.path.dirname(__file__), 'comics.db')


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db():
    conn = get_db()
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS comics (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            file_path TEXT UNIQUE NOT NULL,
            publisher TEXT,
            series TEXT,
            issue_number TEXT,
            page_count INTEGER DEFAULT 0,
            added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
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
