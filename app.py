import json as _json
import os
import platform as _platform
import re
import shutil
import subprocess
import threading
import time
from flask import Flask, render_template, redirect, url_for, request, jsonify, Response, abort
from werkzeug.utils import secure_filename
from database import get_db
from comic_reader import get_page, get_page_count, cbr_tool_available, _find_bin
from config import get_data_dir, get_resource_dir
from onboarding import is_onboarding_done, get_library_path, save_config, load_config, get_reader_mode, get_autoplay_interval
from scanner import scan_library, get_status as get_scan_status

_resource = get_resource_dir()
_data     = get_data_dir()

app = Flask(
    __name__,
    template_folder=os.path.join(_resource, 'templates'),
    static_folder=os.path.join(_resource, 'static'),
)

def _comics_dir():
    return get_library_path() or os.path.expanduser('~/Downloads/Comics')

SUPPORTED_EXTENSIONS = {'.cbz', '.cbr', '.pdf', '.jpg', '.jpeg', '.png'}

COVER_CACHE_DIR = os.path.join(_data, 'covers')
os.makedirs(COVER_CACHE_DIR, exist_ok=True)

UPLOAD_DIR = os.path.join(_data, 'user_comics')
os.makedirs(UPLOAD_DIR, exist_ok=True)

app.config['MAX_CONTENT_LENGTH'] = 5 * 1024 * 1024 * 1024  # 5 GB


@app.errorhandler(413)
def too_large(_e):
    return jsonify({'ok': False, 'error': 'File too large'}), 413

PLACEHOLDER_SVG = '''<svg xmlns="http://www.w3.org/2000/svg" width="200" height="300" viewBox="0 0 200 300">
  <rect width="200" height="300" fill="#1e1e2e"/>
  <rect x="20" y="20" width="160" height="260" fill="none" stroke="#333" stroke-width="2"/>
  <text x="100" y="155" text-anchor="middle" fill="#444" font-family="sans-serif" font-size="13">No Cover</text>
</svg>'''


def natural_sort_key(s):
    return [int(c) if c.isdigit() else c.lower() for c in re.split(r'(\d+)', s or '')]


def extract_metadata_upload(filename):
    """Minimal metadata from just a filename (for browser-uploaded files)."""
    title = os.path.splitext(filename)[0]
    match = re.search(r'(?:v|vol|volume|#|issue)[\s.]?(\d+)', title, re.IGNORECASE)
    return {'publisher': 'Unknown', 'series': 'General', 'title': title,
            'issue_number': match.group(1) if match else None}


# ── Library ──────────────────────────────────────────────────────────────────

@app.route('/')
def index():
    if not is_onboarding_done():
        return redirect(url_for('onboarding'))
    db = get_db()
    publisher_filter = request.args.get('publisher', 'All')
    search       = request.args.get('q', '').strip()
    sort         = request.args.get('sort', 'publisher')
    view         = request.args.get('view', 'series')
    char_filter  = request.args.get('character', '').strip()
    series_filter = request.args.get('series', '').strip()

    publishers = [r['publisher'] for r in db.execute(
        "SELECT DISTINCT publisher FROM comics ORDER BY publisher"
    ).fetchall()]
    total = db.execute("SELECT COUNT(*) FROM comics").fetchone()[0]
    reading_list_count = db.execute("SELECT COUNT(*) FROM reading_list").fetchone()[0]
    continuing = db.execute("""
        SELECT c.id, c.title, c.series, c.publisher, c.page_count,
               rp.current_page as progress
        FROM reading_progress rp
        JOIN comics c ON rp.comic_id = c.id
        WHERE rp.current_page > 0
          AND (c.page_count = 0 OR rp.current_page < c.page_count - 2)
        ORDER BY rp.last_read DESC LIMIT 5
    """).fetchall()
    has_cbr = (not cbr_tool_available()) and (
        db.execute("SELECT 1 FROM comics WHERE file_path LIKE '%.cbr' LIMIT 1").fetchone() is not None
    )

    # ── Character / Series view ───────────────────────────────────────────────
    if view == 'series' and not search:
        pub_cond = "AND c.publisher = ?" if publisher_filter != 'All' else ""
        pub_params = [publisher_filter] if publisher_filter != 'All' else []

        if char_filter and series_filter:
            status_filter = request.args.get('status', '').strip()
            order_sql = {
                'title':  "c.title",
                'added':  "c.added_at DESC",
            }.get(sort, "COALESCE(c.position, c.issue_number, 0), c.title")
            status_cond = {
                'unread':      "AND (rp.current_page IS NULL OR rp.current_page = 0)",
                'in-progress': "AND rp.current_page > 0 AND (c.page_count = 0 OR rp.current_page < c.page_count - 2)",
                'finished':    "AND c.page_count > 0 AND rp.current_page >= c.page_count - 2",
            }.get(status_filter, "")
            rows = db.execute(f"""
                SELECT c.*, COALESCE(rp.current_page, 0) as progress,
                       COALESCE(r.rating, 0) as rating,
                       CASE WHEN f.comic_id  IS NOT NULL THEN 1 ELSE 0 END as is_favorite,
                       CASE WHEN rl.comic_id IS NOT NULL THEN 1 ELSE 0 END as in_reading_list
                FROM comics c
                LEFT JOIN reading_progress rp ON c.id = rp.comic_id
                LEFT JOIN ratings r           ON c.id = r.comic_id
                LEFT JOIN favorites f         ON c.id = f.comic_id
                LEFT JOIN reading_list rl     ON c.id = rl.comic_id
                WHERE COALESCE(c.character, c.series) = ? AND c.series = ? {pub_cond} {status_cond}
                ORDER BY {order_sql}
            """, [char_filter, series_filter] + pub_params).fetchall()
            actual_pub = publisher_filter if publisher_filter != 'All' else (rows[0]['publisher'] if rows else '')
            sm = db.execute(
                "SELECT description, custom_cover_id FROM series_meta WHERE publisher = ? AND series = ?",
                (actual_pub, series_filter)
            ).fetchone()
            all_runs = db.execute("SELECT id, title FROM runs ORDER BY title").fetchall()
            db.close()
            return render_template('index.html',
                                   view='series', series_level='issues',
                                   comics=rows, series_groups=[],
                                   char_filter=char_filter, series_filter=series_filter,
                                   publishers=publishers, current_publisher=publisher_filter,
                                   search=search, sort=sort, total=total,
                                   reading_list_count=reading_list_count,
                                   status_filter=status_filter,
                                   continuing=[],
                                   series_description=sm['description'] if sm else '',
                                   series_publisher=actual_pub,
                                   all_runs=all_runs,
                                   unrar_missing=has_cbr,
                                   library_path=_comics_dir(),
                                   scan_status=get_scan_status())

        if char_filter:
            # Drill-down: show series cards for a specific character.
            # Match on COALESCE so comics filed directly as Publisher/Robin/file.cbz
            # (character=None, series='Robin') show up alongside character='Robin' ones.
            rows = db.execute(f"""
                SELECT c.publisher, c.character, c.series,
                       COUNT(*) as issue_count,
                       COALESCE(sm.custom_cover_id, MIN(c.id)) as cover_id,
                       SUM(CASE WHEN rp.current_page > 0 THEN 1 ELSE 0 END) as started,
                       SUM(CASE WHEN c.page_count > 0 AND rp.current_page >= c.page_count - 1 THEN 1 ELSE 0 END) as completed,
                       COALESCE(sm.description, '') as description,
                       (SELECT c2.id FROM comics c2
                        LEFT JOIN reading_progress rp2 ON c2.id = rp2.comic_id
                        WHERE c2.series = c.series AND c2.publisher = c.publisher
                          AND (c2.character IS c.character)
                          AND NOT (c2.page_count > 0 AND COALESCE(rp2.current_page, 0) >= c2.page_count - 2)
                        ORDER BY COALESCE(c2.position, 0), c2.title LIMIT 1) as resume_id
                FROM comics c
                LEFT JOIN reading_progress rp ON c.id = rp.comic_id
                LEFT JOIN series_meta sm ON sm.publisher = c.publisher AND sm.series = c.series
                WHERE COALESCE(c.character, c.series) = ? {pub_cond}
                GROUP BY c.publisher, c.character, c.series
                ORDER BY c.series
            """, [char_filter] + pub_params).fetchall()
            db.close()
            return render_template('index.html',
                                   view='series', series_level='series',
                                   series_groups=rows, char_filter=char_filter,
                                   comics=[], publishers=publishers,
                                   current_publisher=publisher_filter,
                                   search=search, sort=sort, total=total,
                                   reading_list_count=reading_list_count,
                                   status_filter='',
                                   continuing=[], series_filter='',
                                   unrar_missing=has_cbr,
                                   library_path=_comics_dir(),
                                   scan_status=get_scan_status())
        else:
            # Top level: show character cards (or series if no character subfolder)
            rows = db.execute(f"""
                SELECT c.publisher,
                       COALESCE(c.character, c.series) as group_name,
                       c.character,
                       COUNT(*) as issue_count,
                       MIN(c.id) as cover_id,
                       SUM(CASE WHEN rp.current_page > 0 THEN 1 ELSE 0 END) as started,
                       SUM(CASE WHEN c.page_count > 0 AND rp.current_page >= c.page_count - 1 THEN 1 ELSE 0 END) as completed,
                       (SELECT c2.id FROM comics c2
                        LEFT JOIN reading_progress rp2 ON c2.id = rp2.comic_id
                        WHERE COALESCE(c2.character, c2.series) = COALESCE(c.character, c.series)
                          AND c2.publisher = c.publisher
                          AND NOT (c2.page_count > 0 AND COALESCE(rp2.current_page, 0) >= c2.page_count - 2)
                        ORDER BY c2.series, COALESCE(c2.position, 0), c2.title LIMIT 1) as resume_id
                FROM comics c
                LEFT JOIN reading_progress rp ON c.id = rp.comic_id
                WHERE 1=1 {pub_cond}
                GROUP BY c.publisher, COALESCE(c.character, c.series)
                ORDER BY c.publisher, group_name
            """, pub_params).fetchall()
            db.close()
            return render_template('index.html',
                                   view='series', series_level='character',
                                   series_groups=rows, char_filter='',
                                   comics=[], publishers=publishers,
                                   current_publisher=publisher_filter,
                                   search=search, sort=sort, total=total,
                                   reading_list_count=reading_list_count,
                                   status_filter='',
                                   continuing=continuing, series_filter='',
                                   unrar_missing=has_cbr,
                                   library_path=_comics_dir(),
                                   scan_status=get_scan_status())

    # ── Comics list view ──────────────────────────────────────────────────────
    query = """
        SELECT c.*, COALESCE(rp.current_page, 0) as progress,
               COALESCE(r.rating, 0) as rating,
               CASE WHEN f.comic_id  IS NOT NULL THEN 1 ELSE 0 END as is_favorite,
               CASE WHEN rl.comic_id IS NOT NULL THEN 1 ELSE 0 END as in_reading_list
        FROM comics c
        LEFT JOIN reading_progress rp ON c.id = rp.comic_id
        LEFT JOIN ratings r           ON c.id = r.comic_id
        LEFT JOIN favorites f         ON c.id = f.comic_id
        LEFT JOIN reading_list rl     ON c.id = rl.comic_id
    """
    params = []
    conditions = []

    if view == 'reading-list':
        conditions.append("c.id IN (SELECT comic_id FROM reading_list)")
    elif publisher_filter != 'All':
        conditions.append("c.publisher = ?")
        params.append(publisher_filter)
    if char_filter:
        conditions.append("c.character = ?")
        params.append(char_filter)
    if series_filter:
        conditions.append("c.series = ?")
        params.append(series_filter)
    if search:
        conditions.append("(c.title LIKE ? OR c.series LIKE ?)")
        params.extend([f'%{search}%', f'%{search}%'])
    if conditions:
        query += " WHERE " + " AND ".join(conditions)
    order = {
        'title':    "c.title",
        'added':    "c.added_at DESC",
        'rating':   "COALESCE(r.rating, 0) DESC, c.title",
        'progress': "CASE WHEN c.page_count > 0 THEN CAST(rp.current_page AS FLOAT)/c.page_count ELSE 0 END DESC",
        'manual':   "COALESCE(c.position, c.id), c.id",
    }.get(sort, "c.publisher, c.series, c.title")
    query += f" ORDER BY {order}"

    comics = db.execute(query, params).fetchall()
    if sort == 'title':
        comics = sorted(comics, key=lambda c: natural_sort_key(c['title']))
    elif sort not in ('added', 'rating', 'progress', 'manual'):
        comics = sorted(comics, key=lambda c: (
            natural_sort_key(c['publisher']),
            natural_sort_key(c['series']),
            natural_sort_key(c['title'])
        ))
    db.close()

    return render_template('index.html',
                           comics=comics,
                           series_groups=[],
                           publishers=publishers,
                           current_publisher=publisher_filter,
                           search=search,
                           sort=sort,
                           view=view,
                           series_level='',
                           status_filter='',
                           char_filter=char_filter,
                           series_filter=series_filter,
                           total=total,
                           reading_list_count=reading_list_count,
                           continuing=continuing,
                           unrar_missing=has_cbr,
                           library_path=_comics_dir(),
                           scan_status=get_scan_status())


# ── Images ───────────────────────────────────────────────────────────────────

def _cover_cache_path(comic_id, mime):
    ext = 'png' if mime == 'image/png' else 'jpg'
    return os.path.join(COVER_CACHE_DIR, f'{comic_id}.{ext}')


@app.route('/cover/<int:comic_id>')
def serve_cover(comic_id):
    # Serve from disk cache if available
    for ext, mime in (('jpg', 'image/jpeg'), ('png', 'image/png')):
        path = os.path.join(COVER_CACHE_DIR, f'{comic_id}.{ext}')
        if os.path.exists(path):
            with open(path, 'rb') as f:
                resp = Response(f.read(), mimetype=mime)
                resp.headers['Cache-Control'] = 'public, max-age=86400'
                return resp

    db = get_db()
    row = db.execute("SELECT file_path FROM comics WHERE id = ?", (comic_id,)).fetchone()
    db.close()
    if not row:
        return Response(PLACEHOLDER_SVG, mimetype='image/svg+xml')
    img_data, mime = get_page(row['file_path'], 0)
    if not img_data:
        return Response(PLACEHOLDER_SVG, mimetype='image/svg+xml')

    # Write to disk cache for next time
    try:
        with open(_cover_cache_path(comic_id, mime), 'wb') as f:
            f.write(img_data)
    except Exception as e:
        print(f"Cover cache write failed for {comic_id}: {e}")

    resp = Response(img_data, mimetype=mime)
    resp.headers['Cache-Control'] = 'public, max-age=86400'
    return resp


@app.route('/page/<int:comic_id>/<int:page_num>')
def serve_page(comic_id, page_num):
    db = get_db()
    row = db.execute("SELECT file_path FROM comics WHERE id = ?", (comic_id,)).fetchone()
    db.close()
    if not row:
        abort(404)
    img_data, mime = get_page(row['file_path'], page_num)
    if not img_data:
        abort(404)
    resp = Response(img_data, mimetype=mime)
    resp.headers['Cache-Control'] = 'public, max-age=3600'
    return resp


# ── Upload ───────────────────────────────────────────────────────────────────

@app.route('/upload', methods=['POST'])
def upload_comic():
    f = request.files.get('file')
    if not f or not f.filename:
        return jsonify({'ok': False, 'error': 'No file'})
    ext = os.path.splitext(f.filename)[1].lower()
    if ext not in SUPPORTED_EXTENSIONS:
        return jsonify({'ok': False, 'error': f'Unsupported format: {ext}'})
    filename = secure_filename(f.filename)
    save_path = os.path.join(UPLOAD_DIR, filename)
    if os.path.exists(save_path):
        base, e2 = os.path.splitext(filename)
        save_path = os.path.join(UPLOAD_DIR, f'{base}_{int(time.time())}{e2}')
    f.save(save_path)
    meta = extract_metadata_upload(f.filename)
    page_count = get_page_count(save_path)
    db = get_db()
    try:
        db.execute(
            """INSERT OR IGNORE INTO comics
               (title, file_path, publisher, series, issue_number, page_count)
               VALUES (?, ?, ?, ?, ?, ?)""",
            (meta['title'], save_path, meta['publisher'],
             meta['series'], meta['issue_number'], page_count)
        )
        db.commit()
    except Exception as ex:
        db.close()
        return jsonify({'ok': False, 'error': str(ex)})
    db.close()
    return jsonify({'ok': True})


# ── Comic Detail ─────────────────────────────────────────────────────────────

@app.route('/comic/<int:comic_id>')
def comic_detail(comic_id):
    db = get_db()
    comic = db.execute("""
        SELECT c.*,
               COALESCE(rp.current_page, 0) as progress,
               COALESCE(r.rating, 0) as rating,
               CASE WHEN f.comic_id  IS NOT NULL THEN 1 ELSE 0 END as is_favorite,
               CASE WHEN rl.comic_id IS NOT NULL THEN 1 ELSE 0 END as in_reading_list
        FROM comics c
        LEFT JOIN reading_progress rp ON c.id = rp.comic_id
        LEFT JOIN ratings r           ON c.id = r.comic_id
        LEFT JOIN favorites f         ON c.id = f.comic_id
        LEFT JOIN reading_list rl     ON c.id = rl.comic_id
        WHERE c.id = ?
    """, (comic_id,)).fetchone()
    runs_featuring = db.execute("""
        SELECT r.id, r.title FROM runs r
        JOIN run_items ri ON r.id = ri.run_id
        WHERE ri.comic_id = ?
        ORDER BY r.title
    """, (comic_id,)).fetchall()
    comic_tags = db.execute("""
        SELECT t.id, t.name FROM tags t
        JOIN comic_tags ct ON t.id = ct.tag_id
        WHERE ct.comic_id = ? ORDER BY t.name
    """, (comic_id,)).fetchall()
    all_tags = db.execute("SELECT id, name FROM tags ORDER BY name").fetchall()
    db.close()
    if not comic:
        abort(404)
    return render_template('comic_detail.html', comic=comic,
                           runs_featuring=runs_featuring,
                           comic_tags=comic_tags, all_tags=all_tags)


@app.route('/comic/<int:comic_id>/edit', methods=['GET', 'POST'])
def edit_comic(comic_id):
    db = get_db()
    comic = db.execute("SELECT * FROM comics WHERE id = ?", (comic_id,)).fetchone()
    if not comic:
        abort(404)
    if request.method == 'POST':
        title     = request.form.get('title', '').strip()
        character = request.form.get('character', '').strip()
        series    = request.form.get('series', '').strip()
        publisher = request.form.get('publisher', '').strip()
        issue_num = request.form.get('issue_number', '').strip()
        if not title:
            db.close()
            return render_template('edit_comic.html', comic=comic, error='Title is required.')
        db.execute(
            "UPDATE comics SET title=?, character=?, series=?, publisher=?, issue_number=? WHERE id=?",
            (title, character or None, series or 'General', publisher or 'Unknown', issue_num or None, comic_id)
        )
        db.commit()
        db.close()
        return redirect(url_for('comic_detail', comic_id=comic_id))
    db.close()
    return render_template('edit_comic.html', comic=comic)


@app.route('/comic/<int:comic_id>/delete', methods=['POST'])
def delete_comic(comic_id):
    db = get_db()
    row = db.execute("SELECT file_path FROM comics WHERE id = ?", (comic_id,)).fetchone()
    # Clean up child rows that lack ON DELETE CASCADE before removing the comic
    db.execute("DELETE FROM reading_progress WHERE comic_id = ?", (comic_id,))
    db.execute("DELETE FROM ratings WHERE comic_id = ?", (comic_id,))
    db.execute("DELETE FROM comics WHERE id = ?", (comic_id,))
    db.commit()
    db.close()
    for ext in ('jpg', 'png'):
        cp = os.path.join(COVER_CACHE_DIR, f'{comic_id}.{ext}')
        if os.path.exists(cp):
            os.remove(cp)
    # Only delete file if it lives in the managed upload dir
    if row and row['file_path'].startswith(UPLOAD_DIR):
        try:
            os.remove(row['file_path'])
        except OSError:
            pass
    return redirect(url_for('index'))


# ── Reader ───────────────────────────────────────────────────────────────────

@app.route('/reader/<int:comic_id>')
def reader(comic_id):
    db = get_db()
    comic = db.execute("""
        SELECT c.*, COALESCE(r.rating, 0) as rating
        FROM comics c
        LEFT JOIN ratings r ON c.id = r.comic_id
        WHERE c.id = ?
    """, (comic_id,)).fetchone()
    if not comic:
        abort(404)

    prog = db.execute(
        "SELECT current_page FROM reading_progress WHERE comic_id = ?", (comic_id,)
    ).fetchone()
    current_page = prog['current_page'] if prog else 0

    # When going back from the next comic, land on the last page
    if request.args.get('start') == 'last' and comic['page_count'] > 0:
        current_page = comic['page_count'] - 1

    run_id = request.args.get('run_id', type=int)
    run_context = prev_comic = next_comic = None

    if run_id:
        run_context = db.execute("SELECT * FROM runs WHERE id = ?", (run_id,)).fetchone()
        items = db.execute(
            """SELECT ri.id, ri.comic_id, c.title FROM run_items ri
               JOIN comics c ON ri.comic_id = c.id
               WHERE ri.run_id = ? ORDER BY ri.position""",
            (run_id,)
        ).fetchall()
        for i, item in enumerate(items):
            if item['comic_id'] == comic_id:
                prev_comic = items[i - 1] if i > 0 else None
                next_comic = items[i + 1] if i < len(items) - 1 else None
                break

    # Next comic in same series (for the "Continue" overlay at end of issue)
    next_series_comic = None
    if not run_context and comic['series'] and comic['series'] != 'General':
        series_comics = db.execute("""
            SELECT id, title, COALESCE(position, id) as pos FROM comics
            WHERE series = ? AND publisher = ?
              AND (character IS ? OR character = ?)
            ORDER BY COALESCE(position, id), title
        """, (comic['series'], comic['publisher'],
              comic['character'], comic['character'])).fetchall()
        ids = [r['id'] for r in series_comics]
        try:
            cur_idx = ids.index(comic_id)
            if cur_idx < len(ids) - 1:
                nid = ids[cur_idx + 1]
                next_series_comic = db.execute(
                    "SELECT id, title FROM comics WHERE id = ?", (nid,)
                ).fetchone()
        except ValueError:
            pass

    db.close()
    return render_template('reader.html',
                           comic=comic,
                           current_page=current_page,
                           existing_rating=comic['rating'] or 0,
                           run_context=run_context,
                           prev_comic=prev_comic,
                           next_comic=next_comic,
                           run_id=run_id,
                           next_series_comic=next_series_comic,
                           reader_mode=get_reader_mode(),
                           autoplay_interval=get_autoplay_interval())


# ── API ──────────────────────────────────────────────────────────────────────

@app.route('/api/mark-read/<int:comic_id>', methods=['POST'])
def mark_read(comic_id):
    db = get_db()
    page_count = db.execute("SELECT page_count FROM comics WHERE id = ?", (comic_id,)).fetchone()
    if not page_count:
        db.close()
        return jsonify({'error': 'Not found'}), 404
    last = max(page_count['page_count'] - 1, 0)
    db.execute(
        """INSERT INTO reading_progress (comic_id, current_page, last_read)
           VALUES (?, ?, CURRENT_TIMESTAMP)
           ON CONFLICT(comic_id) DO UPDATE SET current_page = ?, last_read = CURRENT_TIMESTAMP""",
        (comic_id, last, last)
    )
    db.commit()
    db.close()
    return jsonify({'ok': True})


@app.route('/api/progress/<int:comic_id>', methods=['POST'])
def save_progress(comic_id):
    data = request.get_json(silent=True) or {}
    page = data.get('page', 0)
    try:
        page = max(0, int(page))
    except (TypeError, ValueError):
        page = 0
    db = get_db()
    row = db.execute("SELECT page_count FROM comics WHERE id = ?", (comic_id,)).fetchone()
    if row:
        page = min(page, max(row['page_count'] - 1, 0))
        db.execute(
            """INSERT INTO reading_progress (comic_id, current_page, last_read)
               VALUES (?, ?, CURRENT_TIMESTAMP)
               ON CONFLICT(comic_id) DO UPDATE SET current_page = ?, last_read = CURRENT_TIMESTAMP""",
            (comic_id, page, page)
        )
        db.commit()
    db.close()
    return jsonify({'ok': True})


@app.route('/api/rate/<int:comic_id>', methods=['POST'])
def rate_comic(comic_id):
    data = request.get_json(silent=True) or {}
    review = data.get('review', '')
    try:
        rating = int(data.get('rating', 0))
    except (TypeError, ValueError):
        return jsonify({'error': 'Invalid rating'}), 400
    if not (1 <= rating <= 5):
        return jsonify({'error': 'Invalid rating'}), 400
    db = get_db()
    if review:
        db.execute(
            """INSERT INTO ratings (comic_id, rating, review) VALUES (?, ?, ?)
               ON CONFLICT(comic_id) DO UPDATE SET rating = ?, review = ?""",
            (comic_id, rating, review, rating, review)
        )
    else:
        db.execute(
            """INSERT INTO ratings (comic_id, rating, review) VALUES (?, ?, NULL)
               ON CONFLICT(comic_id) DO UPDATE SET rating = ?""",
            (comic_id, rating, rating)
        )
    db.commit()
    db.close()
    return jsonify({'ok': True})


# ── Runs ─────────────────────────────────────────────────────────────────────

@app.route('/stats')
def stats():
    db = get_db()
    total_comics   = db.execute("SELECT COUNT(*) FROM comics").fetchone()[0]
    read_count     = db.execute("""
        SELECT COUNT(*) FROM reading_progress rp
        JOIN comics c ON rp.comic_id = c.id
        WHERE rp.current_page >= c.page_count - 2 AND c.page_count > 1
    """).fetchone()[0]
    pages_read     = db.execute(
        "SELECT COALESCE(SUM(current_page), 0) FROM reading_progress"
    ).fetchone()[0]
    in_progress    = db.execute("""
        SELECT COUNT(*) FROM reading_progress rp
        JOIN comics c ON rp.comic_id = c.id
        WHERE rp.current_page > 0
          AND (c.page_count = 0 OR rp.current_page < c.page_count - 2)
    """).fetchone()[0]
    fav_count      = db.execute("SELECT COUNT(*) FROM favorites").fetchone()[0]
    runs_count     = db.execute("SELECT COUNT(*) FROM runs").fetchone()[0]
    by_publisher   = db.execute("""
        SELECT publisher, COUNT(*) as count FROM comics
        GROUP BY publisher ORDER BY count DESC
    """).fetchall()
    top_series     = db.execute("""
        SELECT series, publisher, COUNT(*) as count FROM comics
        WHERE series != 'General'
        GROUP BY series ORDER BY count DESC LIMIT 8
    """).fetchall()
    recent_reads   = db.execute("""
        SELECT c.id, c.title, c.publisher, rp.last_read, rp.current_page, c.page_count
        FROM reading_progress rp
        JOIN comics c ON rp.comic_id = c.id
        WHERE rp.current_page > 0
        ORDER BY rp.last_read DESC LIMIT 6
    """).fetchall()
    # Reading activity: daily comic count for the past 52 weeks
    activity_rows = db.execute("""
        SELECT DATE(last_read) as day, COUNT(DISTINCT comic_id) as cnt
        FROM reading_progress
        WHERE last_read >= DATE('now', '-364 days')
        GROUP BY DATE(last_read)
    """).fetchall()
    activity_map = {r['day']: r['cnt'] for r in activity_rows}
    db.close()
    return render_template('stats.html',
        total_comics=total_comics, read_count=read_count,
        pages_read=pages_read, in_progress=in_progress,
        fav_count=fav_count, runs_count=runs_count,
        by_publisher=by_publisher, top_series=top_series,
        recent_reads=recent_reads, activity_map=activity_map)


@app.route('/runs')
def runs():
    db = get_db()
    runs_list = db.execute("""
        SELECT r.*,
               COUNT(ri.id) as comic_count,
               COUNT(CASE WHEN rp.current_page >= c.page_count - 2 AND c.page_count > 1 THEN 1 END) as read_count
        FROM runs r
        LEFT JOIN run_items ri ON r.id = ri.run_id
        LEFT JOIN comics c ON ri.comic_id = c.id
        LEFT JOIN reading_progress rp ON c.id = rp.comic_id
        GROUP BY r.id
        ORDER BY r.created_at DESC
    """).fetchall()
    db.close()
    return render_template('runs.html', runs=runs_list)


@app.route('/runs/new', methods=['GET', 'POST'])
def new_run():
    if request.method == 'POST':
        title = request.form.get('title', '').strip()
        description = request.form.get('description', '').strip()
        if not title:
            return render_template('new_run.html', error='A title is required.')
        buy_link = request.form.get('buy_link', '').strip()
        db = get_db()
        cur = db.execute("INSERT INTO runs (title, description, buy_link) VALUES (?, ?, ?)", (title, description, buy_link or None))
        run_id = cur.lastrowid
        db.commit()
        db.close()
        return redirect(url_for('run_detail', run_id=run_id))
    return render_template('new_run.html')


@app.route('/runs/<int:run_id>')
def run_detail(run_id):
    db = get_db()
    run = db.execute("SELECT * FROM runs WHERE id = ?", (run_id,)).fetchone()
    if not run:
        abort(404)

    items = db.execute("""
        SELECT ri.id, ri.position, ri.notes,
               c.id as comic_id, c.title, c.series, c.publisher, c.issue_number, c.page_count,
               COALESCE(rp.current_page, 0) as progress,
               COALESCE(r.rating, 0) as rating,
               CASE WHEN f.comic_id IS NOT NULL THEN 1 ELSE 0 END as is_favorite
        FROM run_items ri
        JOIN comics c ON ri.comic_id = c.id
        LEFT JOIN reading_progress rp ON c.id = rp.comic_id
        LEFT JOIN ratings r ON c.id = r.comic_id
        LEFT JOIN favorites f ON c.id = f.comic_id
        WHERE ri.run_id = ?
        ORDER BY ri.position
    """, (run_id,)).fetchall()

    all_comics = db.execute("""
        SELECT id, title, series, publisher FROM comics
        WHERE id NOT IN (SELECT comic_id FROM run_items WHERE run_id = ?)
    """, (run_id,)).fetchall()
    all_comics = sorted(all_comics, key=lambda c: (
        natural_sort_key(c['publisher']),
        natural_sort_key(c['series']),
        natural_sort_key(c['title'])
    ))

    # Resume point: first comic that isn't finished (progress < page_count - 2)
    resume_comic_id = None
    for item in items:
        if item['page_count'] == 0 or item['progress'] < item['page_count'] - 2:
            resume_comic_id = item['comic_id']
            break
    if resume_comic_id is None and items:
        resume_comic_id = items[0]['comic_id']  # all done — start over from top

    db.close()
    return render_template('run_detail.html', run=run, items=items, all_comics=all_comics,
                           resume_comic_id=resume_comic_id)


@app.route('/runs/<int:run_id>/edit', methods=['GET', 'POST'])
def edit_run(run_id):
    db = get_db()
    run = db.execute("SELECT * FROM runs WHERE id = ?", (run_id,)).fetchone()
    if not run:
        abort(404)
    if request.method == 'POST':
        title = request.form.get('title', '').strip()
        description = request.form.get('description', '').strip()
        buy_link = request.form.get('buy_link', '').strip()
        if not title:
            db.close()
            return render_template('edit_run.html', run=run, error='A title is required.')
        db.execute(
            "UPDATE runs SET title = ?, description = ?, buy_link = ? WHERE id = ?",
            (title, description or None, buy_link or None, run_id)
        )
        db.commit()
        db.close()
        return redirect(url_for('run_detail', run_id=run_id))
    db.close()
    return render_template('edit_run.html', run=run)


@app.route('/runs/<int:run_id>/add', methods=['POST'])
def add_to_run(run_id):
    comic_id = request.form.get('comic_id', type=int)
    if comic_id:
        db = get_db()
        max_pos = db.execute(
            "SELECT COALESCE(MAX(position), 0) FROM run_items WHERE run_id = ?", (run_id,)
        ).fetchone()[0]
        db.execute(
            "INSERT OR IGNORE INTO run_items (run_id, comic_id, position) VALUES (?, ?, ?)",
            (run_id, comic_id, max_pos + 1)
        )
        db.commit()
        db.close()
    return redirect(url_for('run_detail', run_id=run_id))


@app.route('/runs/<int:run_id>/remove/<int:item_id>', methods=['POST'])
def remove_from_run(run_id, item_id):
    db = get_db()
    db.execute("DELETE FROM run_items WHERE id = ? AND run_id = ?", (item_id, run_id))
    db.commit()
    db.close()
    return redirect(url_for('run_detail', run_id=run_id))


@app.route('/api/rate-run/<int:run_id>', methods=['POST'])
def rate_run(run_id):
    data = request.get_json(silent=True) or {}
    review = data.get('review', '')
    try:
        rating = int(data.get('rating', 0))
    except (TypeError, ValueError):
        return jsonify({'error': 'Invalid rating'}), 400
    if not (1 <= rating <= 5):
        return jsonify({'error': 'Invalid rating'}), 400
    db = get_db()
    db.execute("UPDATE runs SET rating = ?, review = ? WHERE id = ?", (rating, review, run_id))
    db.commit()
    db.close()
    return jsonify({'ok': True})


@app.route('/api/favorite/<int:comic_id>', methods=['POST'])
def toggle_favorite(comic_id):
    db = get_db()
    existing = db.execute("SELECT 1 FROM favorites WHERE comic_id = ?", (comic_id,)).fetchone()
    if existing:
        db.execute("DELETE FROM favorites WHERE comic_id = ?", (comic_id,))
        is_fav = False
    else:
        db.execute("INSERT INTO favorites (comic_id) VALUES (?)", (comic_id,))
        is_fav = True
    db.commit()
    db.close()
    return jsonify({'ok': True, 'favorite': is_fav})


@app.route('/api/note/<int:item_id>', methods=['POST'])
def save_note(item_id):
    note = (request.get_json(silent=True) or {}).get('note', '')
    db = get_db()
    db.execute("UPDATE run_items SET notes = ? WHERE id = ?", (note or None, item_id))
    db.commit()
    db.close()
    return jsonify({'ok': True})


@app.route('/api/runs/<int:run_id>/reorder', methods=['POST'])
def reorder_run(run_id):
    order = (request.get_json(silent=True) or {}).get('order', [])
    db = get_db()
    for pos, item_id in enumerate(order, 1):
        db.execute("UPDATE run_items SET position = ? WHERE id = ? AND run_id = ?",
                   (pos, item_id, run_id))
    db.commit()
    db.close()
    return jsonify({'ok': True})


@app.route('/api/comic/<int:comic_id>/tags', methods=['POST'])
def add_comic_tag(comic_id):
    name = (request.get_json(silent=True) or {}).get('name', '').strip().lower()
    if not name:
        return jsonify({'error': 'Name required'}), 400
    db = get_db()
    tag = db.execute("SELECT id FROM tags WHERE name = ?", (name,)).fetchone()
    if tag:
        tag_id = tag['id']
    else:
        cur = db.execute("INSERT INTO tags (name) VALUES (?)", (name,))
        tag_id = cur.lastrowid
    db.execute("INSERT OR IGNORE INTO comic_tags (comic_id, tag_id) VALUES (?, ?)",
               (comic_id, tag_id))
    db.commit()
    db.close()
    return jsonify({'ok': True, 'id': tag_id, 'name': name})


@app.route('/api/comic/<int:comic_id>/tags/<int:tag_id>', methods=['DELETE'])
def remove_comic_tag(comic_id, tag_id):
    db = get_db()
    db.execute("DELETE FROM comic_tags WHERE comic_id = ? AND tag_id = ?",
               (comic_id, tag_id))
    db.commit()
    db.close()
    return jsonify({'ok': True})


@app.route('/runs/<int:run_id>/delete', methods=['POST'])
def delete_run(run_id):
    db = get_db()
    db.execute("DELETE FROM runs WHERE id = ?", (run_id,))
    db.commit()
    db.close()
    return redirect(url_for('runs'))


@app.route('/api/library/reorder', methods=['POST'])
def reorder_library():
    order = (request.get_json(silent=True) or {}).get('order', [])
    db = get_db()
    for pos, comic_id in enumerate(order, 1):
        db.execute("UPDATE comics SET position = ? WHERE id = ?", (pos, comic_id))
    db.commit()
    db.close()
    return jsonify({'ok': True})


@app.route('/library/clear', methods=['POST'])
def clear_library():
    db = get_db()
    comics = db.execute("SELECT id, file_path FROM comics").fetchall()
    db.execute("DELETE FROM reading_progress")
    db.execute("DELETE FROM ratings")
    db.execute("DELETE FROM favorites")
    db.execute("DELETE FROM comic_tags")
    db.execute("DELETE FROM run_items")
    db.execute("DELETE FROM comics")
    db.commit()
    db.close()
    for f in os.listdir(COVER_CACHE_DIR):
        try:
            os.remove(os.path.join(COVER_CACHE_DIR, f))
        except OSError:
            pass
    for comic in comics:
        if comic['file_path'].startswith(UPLOAD_DIR):
            try:
                os.remove(comic['file_path'])
            except OSError:
                pass
    return redirect(url_for('index'))


# ── Onboarding ───────────────────────────────────────────────────────────────

@app.route('/onboarding')
def onboarding():
    if is_onboarding_done():
        return redirect(url_for('index'))
    return render_template('onboarding.html')


@app.route('/api/onboarding/scan-start', methods=['POST'])
def onboarding_scan_start():
    data = request.get_json(silent=True) or {}
    path = data.get('library_path', '').strip()
    path = os.path.expanduser(path)
    if not path or not os.path.isdir(path):
        return jsonify({'ok': False, 'error': 'Folder not found. Please choose a valid folder.'})
    save_config({'library_path': path})
    scan_library(path)
    return jsonify({'ok': True})


@app.route('/api/onboarding/complete', methods=['POST'])
def onboarding_complete():
    data = request.get_json(silent=True) or {}
    reader_mode = data.get('reader_mode', 'page')
    save_config({'reader_mode': reader_mode, 'onboarding_done': True})
    return jsonify({'ok': True})


@app.route('/api/scan/status')
def scan_status():
    return jsonify(get_scan_status())


@app.route('/api/scan/start', methods=['POST'])
def scan_start():
    path = _comics_dir()
    ok = scan_library(path)
    return jsonify({'ok': ok, 'path': path})


# ── Settings ─────────────────────────────────────────────────────────────────

_cbr_install_state = {'running': False, 'log': '', 'done': False, 'ok': False}


@app.route('/settings')
def settings():
    cfg = load_config()
    system = _platform.system()
    return render_template('settings.html',
                           library_path=cfg.get('library_path', ''),
                           reader_mode=cfg.get('reader_mode', 'page'),
                           autoplay_interval=int(cfg.get('autoplay_interval', 10)),
                           cbr_ok=cbr_tool_available(),
                           brew_ok=bool(shutil.which('brew') or _find_bin('brew')),
                           platform=system,
                           scan_status=get_scan_status())


@app.route('/api/settings/save', methods=['POST'])
def settings_save():
    data = request.get_json(silent=True) or {}
    updates = {}
    if 'library_path' in data:
        path = os.path.expanduser(data['library_path'].strip())
        if not os.path.isdir(path):
            return jsonify({'ok': False, 'error': 'Folder not found'})
        updates['library_path'] = path
        scan_library(path)
    if 'reader_mode' in data:
        updates['reader_mode'] = data['reader_mode']
    if 'autoplay_interval' in data:
        val = data['autoplay_interval']
        try:
            updates['autoplay_interval'] = max(3, min(30, int(val)))
        except (TypeError, ValueError):
            pass
    if updates:
        save_config(updates)
    return jsonify({'ok': True})


@app.route('/api/settings/install-cbr', methods=['POST'])
def install_cbr():
    if _cbr_install_state['running']:
        return jsonify({'ok': False, 'error': 'Already running'})

    system = _platform.system()

    if system == 'Windows':
        return jsonify({'ok': False, 'error': 'manual', 'platform': 'Windows'})

    if system == 'Linux':
        pkg_mgr = (shutil.which('apt-get') and ['apt-get', 'install', '-y', 'unar']) or \
                  (shutil.which('dnf')     and ['dnf', 'install', '-y', 'unar']) or \
                  (shutil.which('pacman')  and ['pacman', '-S', '--noconfirm', 'unar'])
        if not pkg_mgr:
            return jsonify({'ok': False, 'error': 'manual', 'platform': 'Linux'})
        def _run_linux():
            _cbr_install_state.update({'running': True, 'log': '', 'done': False, 'ok': False})
            try:
                proc = subprocess.Popen(
                    pkg_mgr,
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
                )
                for line in proc.stdout:
                    _cbr_install_state['log'] += line
                proc.wait()
                _cbr_install_state['ok'] = proc.returncode == 0
            except Exception as e:
                _cbr_install_state['log'] += f'\nError: {e}'
            finally:
                _cbr_install_state['running'] = False
                _cbr_install_state['done'] = True
        threading.Thread(target=_run_linux, daemon=True).start()
        return jsonify({'ok': True})

    # macOS
    brew = shutil.which('brew') or _find_bin('brew')
    if not brew:
        return jsonify({'ok': False, 'error': 'Homebrew not found'})

    def _run():
        _cbr_install_state.update({'running': True, 'log': '', 'done': False, 'ok': False})
        try:
            proc = subprocess.Popen(
                [brew, 'install', 'unar'],
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True
            )
            for line in proc.stdout:
                _cbr_install_state['log'] += line
            proc.wait()
            _cbr_install_state['ok'] = proc.returncode == 0
        except Exception as e:
            _cbr_install_state['log'] += f'\nError: {e}'
        finally:
            _cbr_install_state['running'] = False
            _cbr_install_state['done'] = True

    threading.Thread(target=_run, daemon=True).start()
    return jsonify({'ok': True})


@app.route('/api/settings/cbr-status')
def cbr_install_status():
    from comic_reader import cbr_tool_available
    return jsonify({**_cbr_install_state, 'cbr_ok': cbr_tool_available()})


@app.route('/api/settings/reset-setup', methods=['POST'])
def reset_setup():
    save_config({'onboarding_done': False})
    return jsonify({'ok': True})


# ── Mark unread ───────────────────────────────────────────────────────────────

@app.route('/api/reset-progress/<int:comic_id>', methods=['POST'])
def reset_progress(comic_id):
    db = get_db()
    db.execute("DELETE FROM reading_progress WHERE comic_id = ?", (comic_id,))
    db.commit()
    db.close()
    return jsonify({'ok': True})


# ── Reading list ──────────────────────────────────────────────────────────────

@app.route('/api/reading-list/<int:comic_id>', methods=['POST'])
def toggle_reading_list(comic_id):
    db = get_db()
    existing = db.execute("SELECT 1 FROM reading_list WHERE comic_id = ?", (comic_id,)).fetchone()
    if existing:
        db.execute("DELETE FROM reading_list WHERE comic_id = ?", (comic_id,))
        in_list = False
    else:
        db.execute("INSERT OR IGNORE INTO reading_list (comic_id) VALUES (?)", (comic_id,))
        in_list = True
    db.commit()
    db.close()
    return jsonify({'ok': True, 'in_list': in_list})


# ── Bulk operations ───────────────────────────────────────────────────────────

@app.route('/api/bulk/delete', methods=['POST'])
def bulk_delete():
    ids = (request.get_json(silent=True) or {}).get('ids', [])
    if not ids:
        return jsonify({'ok': True})
    db = get_db()
    ph  = ','.join('?' * len(ids))
    rows = db.execute(f"SELECT id, file_path FROM comics WHERE id IN ({ph})", ids).fetchall()
    db.execute(f"DELETE FROM reading_progress WHERE comic_id IN ({ph})", ids)
    db.execute(f"DELETE FROM ratings WHERE comic_id IN ({ph})", ids)
    db.execute(f"DELETE FROM comics WHERE id IN ({ph})", ids)
    db.commit()
    db.close()
    for row in rows:
        for ext in ('jpg', 'png'):
            cp = os.path.join(COVER_CACHE_DIR, f'{row["id"]}.{ext}')
            if os.path.exists(cp):
                try: os.remove(cp)
                except OSError: pass
        if row['file_path'].startswith(UPLOAD_DIR):
            try: os.remove(row['file_path'])
            except OSError: pass
    return jsonify({'ok': True})


@app.route('/api/bulk/mark-read', methods=['POST'])
def bulk_mark_read():
    ids = (request.get_json(silent=True) or {}).get('ids', [])
    if not ids:
        return jsonify({'ok': True})
    db = get_db()
    ph = ','.join('?' * len(ids))
    db.execute(f"""
        INSERT INTO reading_progress (comic_id, current_page, last_read)
        SELECT id, MAX(page_count - 1, 0), CURRENT_TIMESTAMP
        FROM comics WHERE id IN ({ph}) AND page_count > 0
        ON CONFLICT(comic_id) DO UPDATE
          SET current_page = excluded.current_page,
              last_read    = CURRENT_TIMESTAMP
    """, ids)
    db.commit()
    db.close()
    return jsonify({'ok': True})


@app.route('/api/bulk/mark-unread', methods=['POST'])
def bulk_mark_unread():
    ids = (request.get_json(silent=True) or {}).get('ids', [])
    db = get_db()
    for comic_id in ids:
        db.execute("DELETE FROM reading_progress WHERE comic_id = ?", (comic_id,))
    db.commit()
    db.close()
    return jsonify({'ok': True})


@app.route('/api/bulk/reading-list', methods=['POST'])
def bulk_reading_list():
    data   = request.get_json(silent=True) or {}
    ids    = data.get('ids', [])
    action = data.get('action', 'add')
    db = get_db()
    for comic_id in ids:
        if action == 'add':
            db.execute("INSERT OR IGNORE INTO reading_list (comic_id) VALUES (?)", (comic_id,))
        else:
            db.execute("DELETE FROM reading_list WHERE comic_id = ?", (comic_id,))
    db.commit()
    db.close()
    return jsonify({'ok': True})


# ── Series Metadata ───────────────────────────────────────────────────────────

@app.route('/api/series-meta', methods=['GET', 'POST'])
def series_meta():
    if request.method == 'GET':
        publisher = request.args.get('publisher', '').strip()
        series    = request.args.get('series', '').strip()
        db = get_db()
        # Resolve 'All' to the actual publisher for this series
        if not publisher or publisher == 'All':
            row = db.execute("SELECT publisher FROM comics WHERE series = ? LIMIT 1", (series,)).fetchone()
            publisher = row['publisher'] if row else ''
        sm = db.execute(
            "SELECT description, custom_cover_id FROM series_meta WHERE publisher = ? AND series = ?",
            (publisher, series)
        ).fetchone()
        covers = db.execute(
            "SELECT id, title FROM comics WHERE publisher = ? AND series = ? ORDER BY COALESCE(position, 0), title",
            (publisher, series)
        ).fetchall()
        db.close()
        return jsonify({
            'description':     sm['description'] if sm else '',
            'custom_cover_id': sm['custom_cover_id'] if sm else None,
            'covers':          [{'id': c['id'], 'title': c['title']} for c in covers],
            'resolved_publisher': publisher,
        })
    data      = request.get_json(silent=True) or {}
    publisher = data.get('publisher', '').strip()
    series    = data.get('series', '').strip()
    desc      = data.get('description', '').strip()
    cover_id  = data.get('custom_cover_id')
    if not publisher or not series:
        return jsonify({'ok': False, 'error': 'publisher and series required'}), 400
    db = get_db()
    db.execute(
        """INSERT INTO series_meta (publisher, series, description, custom_cover_id)
           VALUES (?, ?, ?, ?)
           ON CONFLICT(publisher, series) DO UPDATE
             SET description = excluded.description,
                 custom_cover_id = excluded.custom_cover_id""",
        (publisher, series, desc, cover_id or None)
    )
    db.commit()
    db.close()
    return jsonify({'ok': True})


# ── Quick-look ────────────────────────────────────────────────────────────────

@app.route('/api/comic/<int:comic_id>/quicklook')
def comic_quicklook(comic_id):
    db = get_db()
    comic = db.execute("""
        SELECT c.id, c.title, c.series, c.publisher, c.issue_number, c.page_count, c.character,
               COALESCE(rp.current_page, 0) as progress,
               COALESCE(r.rating, 0) as rating,
               CASE WHEN f.comic_id  IS NOT NULL THEN 1 ELSE 0 END as is_favorite,
               CASE WHEN rl.comic_id IS NOT NULL THEN 1 ELSE 0 END as in_reading_list
        FROM comics c
        LEFT JOIN reading_progress rp ON c.id = rp.comic_id
        LEFT JOIN ratings r           ON c.id = r.comic_id
        LEFT JOIN favorites f         ON c.id = f.comic_id
        LEFT JOIN reading_list rl     ON c.id = rl.comic_id
        WHERE c.id = ?
    """, (comic_id,)).fetchone()
    if not comic:
        return jsonify({'error': 'Not found'}), 404
    tags = db.execute("""
        SELECT t.name FROM tags t
        JOIN comic_tags ct ON t.id = ct.tag_id
        WHERE ct.comic_id = ? ORDER BY t.name
    """, (comic_id,)).fetchall()
    runs_in = db.execute("""
        SELECT r.id, r.title FROM runs r
        JOIN run_items ri ON r.id = ri.run_id
        WHERE ri.comic_id = ? ORDER BY r.title
    """, (comic_id,)).fetchall()
    all_runs = db.execute("SELECT id, title FROM runs ORDER BY title").fetchall()
    db.close()
    return jsonify({
        'id':            comic['id'],
        'title':         comic['title'],
        'series':        comic['series'],
        'publisher':     comic['publisher'],
        'issue_number':  comic['issue_number'],
        'page_count':    comic['page_count'],
        'progress':      comic['progress'],
        'rating':        comic['rating'],
        'is_favorite':   comic['is_favorite'],
        'in_reading_list': comic['in_reading_list'],
        'tags':          [t['name'] for t in tags],
        'runs_in':       [{'id': r['id'], 'title': r['title']} for r in runs_in],
        'all_runs':      [{'id': r['id'], 'title': r['title']} for r in all_runs],
    })


# ── Series add-to-run ─────────────────────────────────────────────────────────

@app.route('/api/series/add-to-run', methods=['POST'])
def series_add_to_run():
    data      = request.get_json(silent=True) or {}
    run_id    = data.get('run_id')
    publisher = data.get('publisher', '').strip()
    series    = data.get('series', '').strip()
    char      = data.get('character')
    if not run_id or not series:
        return jsonify({'ok': False, 'error': 'run_id and series required'}), 400
    db = get_db()
    # Resolve 'All' to the actual publisher
    if not publisher or publisher == 'All':
        row = db.execute("SELECT publisher FROM comics WHERE series = ? LIMIT 1", (series,)).fetchone()
        publisher = row['publisher'] if row else ''
    if char:
        comics = db.execute(
            """SELECT id FROM comics WHERE series = ? AND publisher = ? AND character = ?
               ORDER BY COALESCE(position, 0), title""",
            (series, publisher, char)
        ).fetchall()
    else:
        comics = db.execute(
            """SELECT id FROM comics WHERE series = ? AND publisher = ?
               ORDER BY COALESCE(position, 0), title""",
            (series, publisher)
        ).fetchall()
    max_pos = db.execute(
        "SELECT COALESCE(MAX(position), 0) FROM run_items WHERE run_id = ?", (run_id,)
    ).fetchone()[0]
    for i, c in enumerate(comics, max_pos + 1):
        db.execute(
            "INSERT OR IGNORE INTO run_items (run_id, comic_id, position) VALUES (?, ?, ?)",
            (run_id, c['id'], i)
        )
    db.commit()
    db.close()
    return jsonify({'ok': True, 'added': len(comics)})


# ── Series mark-read ─────────────────────────────────────────────────────────

@app.route('/api/series/mark-read', methods=['POST'])
def series_mark_read():
    data      = request.get_json(silent=True) or {}
    publisher = data.get('publisher', '').strip()
    series    = data.get('series', '').strip()
    char      = data.get('character') or None
    if not series:
        return jsonify({'ok': False, 'error': 'series required'}), 400
    db = get_db()
    if not publisher or publisher == 'All':
        row = db.execute("SELECT publisher FROM comics WHERE series = ? LIMIT 1", (series,)).fetchone()
        publisher = row['publisher'] if row else ''
    if char:
        comics = db.execute(
            "SELECT id, page_count FROM comics WHERE series = ? AND publisher = ? AND character = ?",
            (series, publisher, char)
        ).fetchall()
    else:
        comics = db.execute(
            "SELECT id, page_count FROM comics WHERE series = ? AND publisher = ?",
            (series, publisher)
        ).fetchall()
    for c in comics:
        last = max((c['page_count'] or 1) - 1, 0)
        db.execute(
            """INSERT INTO reading_progress (comic_id, current_page, last_read)
               VALUES (?, ?, CURRENT_TIMESTAMP)
               ON CONFLICT(comic_id) DO UPDATE
                 SET current_page = excluded.current_page,
                     last_read    = CURRENT_TIMESTAMP""",
            (c['id'], last)
        )
    db.commit()
    db.close()
    return jsonify({'ok': True, 'marked': len(comics)})


# ── Bulk add-to-run ───────────────────────────────────────────────────────────

@app.route('/api/bulk/add-to-run', methods=['POST'])
def bulk_add_to_run():
    data   = request.get_json(silent=True) or {}
    ids    = data.get('ids', [])
    run_id = data.get('run_id')
    if not run_id or not ids:
        return jsonify({'ok': False, 'error': 'run_id and ids required'}), 400
    db = get_db()
    max_pos = db.execute(
        "SELECT COALESCE(MAX(position), 0) FROM run_items WHERE run_id = ?", (run_id,)
    ).fetchone()[0]
    for i, comic_id in enumerate(ids, max_pos + 1):
        db.execute(
            "INSERT OR IGNORE INTO run_items (run_id, comic_id, position) VALUES (?, ?, ?)",
            (run_id, comic_id, i)
        )
    db.commit()
    db.close()
    return jsonify({'ok': True})


# ── Search API ────────────────────────────────────────────────────────────────

@app.route('/api/search')
def search_api():
    q     = request.args.get('q', '').strip()
    limit = min(int(request.args.get('limit', 12)), 40)
    if not q:
        return jsonify({'results': []})
    db = get_db()
    rows = db.execute("""
        SELECT c.id, c.title, c.series, c.publisher, c.page_count,
               COALESCE(rp.current_page, 0) as progress
        FROM comics c
        LEFT JOIN reading_progress rp ON c.id = rp.comic_id
        WHERE c.title LIKE ? OR c.series LIKE ? OR c.publisher LIKE ?
        ORDER BY c.title LIMIT ?
    """, (f'%{q}%', f'%{q}%', f'%{q}%', limit)).fetchall()
    db.close()
    return jsonify({'results': [dict(r) for r in rows]})


# ── Random unread ──────────────────────────────────────────────────────────────

@app.route('/api/random-unread')
def random_unread():
    db = get_db()
    row = db.execute("""
        SELECT c.id FROM comics c
        LEFT JOIN reading_progress rp ON c.id = rp.comic_id
        WHERE rp.current_page IS NULL OR rp.current_page = 0
        ORDER BY RANDOM() LIMIT 1
    """).fetchone()
    db.close()
    return jsonify({'id': row['id'] if row else None})


# ── Import backup ──────────────────────────────────────────────────────────────

@app.route('/api/import', methods=['POST'])
def import_backup():
    data = request.get_json(silent=True) or {}
    db = get_db()
    prog_count = 0
    for item in data.get('reading_progress', []):
        comic_id = item.get('comic_id')
        page     = item.get('current_page', 0)
        ts       = item.get('last_read', 'CURRENT_TIMESTAMP')
        if comic_id and db.execute("SELECT 1 FROM comics WHERE id = ?", (comic_id,)).fetchone():
            db.execute(
                """INSERT INTO reading_progress (comic_id, current_page, last_read) VALUES (?, ?, ?)
                   ON CONFLICT(comic_id) DO UPDATE
                     SET current_page = MAX(current_page, excluded.current_page),
                         last_read = excluded.last_read""",
                (comic_id, page, ts)
            )
            prog_count += 1
    rating_count = 0
    for item in data.get('ratings', []):
        cid = item.get('comic_id')
        if cid and db.execute("SELECT 1 FROM comics WHERE id = ?", (cid,)).fetchone():
            db.execute(
                """INSERT INTO ratings (comic_id, rating, review) VALUES (?, ?, ?)
                   ON CONFLICT(comic_id) DO UPDATE SET rating = excluded.rating""",
                (cid, item.get('rating'), item.get('review'))
            )
            rating_count += 1
    for cid in data.get('favorites', []):
        if db.execute("SELECT 1 FROM comics WHERE id = ?", (cid,)).fetchone():
            db.execute("INSERT OR IGNORE INTO favorites (comic_id) VALUES (?)", (cid,))
    tag_count = 0
    tag_map = {}
    for t in data.get('tags', []):
        existing = db.execute("SELECT id FROM tags WHERE name = ?", (t['name'],)).fetchone()
        if existing:
            tag_map[t['id']] = existing['id']
        else:
            cur = db.execute("INSERT INTO tags (name) VALUES (?)", (t['name'],))
            tag_map[t['id']] = cur.lastrowid
            tag_count += 1
    for ct in data.get('comic_tags', []):
        new_tag_id = tag_map.get(ct['tag_id'])
        cid = ct['comic_id']
        if new_tag_id and db.execute("SELECT 1 FROM comics WHERE id = ?", (cid,)).fetchone():
            db.execute("INSERT OR IGNORE INTO comic_tags (comic_id, tag_id) VALUES (?, ?)",
                       (cid, new_tag_id))
    run_count = 0
    run_map = {}
    for r in data.get('runs', []):
        cur = db.execute(
            "INSERT INTO runs (title, description, created_at) VALUES (?, ?, ?)",
            (r['title'], r.get('description'), r.get('created_at'))
        )
        run_map[r['id']] = cur.lastrowid
        run_count += 1
    for ri in data.get('run_items', []):
        new_run_id = run_map.get(ri['run_id'])
        cid = ri['comic_id']
        if new_run_id and db.execute("SELECT 1 FROM comics WHERE id = ?", (cid,)).fetchone():
            max_pos = db.execute(
                "SELECT COALESCE(MAX(position), 0) FROM run_items WHERE run_id = ?", (new_run_id,)
            ).fetchone()[0]
            db.execute(
                "INSERT OR IGNORE INTO run_items (run_id, comic_id, position) VALUES (?, ?, ?)",
                (new_run_id, cid, ri.get('position', max_pos + 1))
            )
    db.commit()
    db.close()
    return jsonify({'ok': True, 'progress': prog_count, 'ratings': rating_count,
                    'tags': tag_count, 'runs': run_count})


# ── Export ────────────────────────────────────────────────────────────────────

@app.route('/api/export')
def export_library():
    db = get_db()
    data = {
        'exported_at':    time.strftime('%Y-%m-%dT%H:%M:%S'),
        'comics':         [dict(r) for r in db.execute("SELECT * FROM comics").fetchall()],
        'reading_progress': [dict(r) for r in db.execute("SELECT * FROM reading_progress").fetchall()],
        'ratings':        [dict(r) for r in db.execute("SELECT * FROM ratings").fetchall()],
        'favorites':      [r['comic_id'] for r in db.execute("SELECT comic_id FROM favorites").fetchall()],
        'reading_list':   [r['comic_id'] for r in db.execute("SELECT comic_id FROM reading_list").fetchall()],
        'tags':           [dict(r) for r in db.execute("SELECT * FROM tags").fetchall()],
        'comic_tags':     [dict(r) for r in db.execute("SELECT * FROM comic_tags").fetchall()],
        'runs':           [dict(r) for r in db.execute("SELECT * FROM runs").fetchall()],
        'run_items':      [dict(r) for r in db.execute("SELECT * FROM run_items").fetchall()],
    }
    db.close()
    filename = f'comicarc-export-{time.strftime("%Y%m%d")}.json'
    return Response(
        _json.dumps(data, indent=2, default=str),
        mimetype='application/json',
        headers={'Content-Disposition': f'attachment; filename="{filename}"'}
    )
