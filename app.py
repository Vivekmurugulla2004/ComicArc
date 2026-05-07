import os
import re
import time
from flask import Flask, render_template, redirect, url_for, request, jsonify, Response, abort
from werkzeug.utils import secure_filename
from database import get_db, init_db, migrate_db
from comic_reader import get_page, get_page_count, cbr_tool_available

app = Flask(__name__)

COMICS_DIR = os.path.expanduser('~/Downloads/Comics')

SUPPORTED_EXTENSIONS = {'.cbz', '.cbr', '.pdf'}

COVER_CACHE_DIR = os.path.join(os.path.dirname(__file__), 'static', 'covers')
os.makedirs(COVER_CACHE_DIR, exist_ok=True)

UPLOAD_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'user_comics')
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


def extract_metadata_upload(filename):
    """Minimal metadata from just a filename (for browser-uploaded files)."""
    title = os.path.splitext(filename)[0]
    match = re.search(r'(?:v|vol|volume|#|issue)[\s.]?(\d+)', title, re.IGNORECASE)
    return {'publisher': 'Unknown', 'series': 'General', 'title': title,
            'issue_number': match.group(1) if match else None}


def extract_metadata(file_path):
    rel = os.path.relpath(file_path, COMICS_DIR)
    parts = rel.split(os.sep)
    publisher = parts[0] if len(parts) > 1 else 'Unknown'
    filename = parts[-1]
    title = os.path.splitext(filename)[0]

    # Everything between publisher and filename becomes the series.
    # e.g. Marvel/Spider-Man/Classic/file.cbr → "Spider-Man — Classic"
    intermediate = parts[1:-1]
    if not intermediate:
        series = 'General'
    elif len(intermediate) == 1:
        series = intermediate[0]
    else:
        series = ' — '.join(intermediate)

    match = re.search(r'(?:v|vol|volume|#|issue)[\s.]?(\d+)', title, re.IGNORECASE)
    issue_number = match.group(1) if match else None
    return {'publisher': publisher, 'series': series, 'title': title, 'issue_number': issue_number}


# ── Library ──────────────────────────────────────────────────────────────────

@app.route('/')
def index():
    db = get_db()
    publisher_filter = request.args.get('publisher', 'All')
    search = request.args.get('q', '').strip()

    query = """
        SELECT c.*, COALESCE(rp.current_page, 0) as progress,
               COALESCE(r.rating, 0) as rating,
               CASE WHEN f.comic_id IS NOT NULL THEN 1 ELSE 0 END as is_favorite
        FROM comics c
        LEFT JOIN reading_progress rp ON c.id = rp.comic_id
        LEFT JOIN ratings r ON c.id = r.comic_id
        LEFT JOIN favorites f ON c.id = f.comic_id
    """
    params = []
    conditions = []

    if publisher_filter != 'All':
        conditions.append("c.publisher = ?")
        params.append(publisher_filter)
    if search:
        conditions.append("(c.title LIKE ? OR c.series LIKE ?)")
        params.extend([f'%{search}%', f'%{search}%'])
    if conditions:
        query += " WHERE " + " AND ".join(conditions)
    query += " ORDER BY c.publisher, c.series, c.title"

    tag_filter = request.args.get('tag', '').strip()
    if tag_filter:
        conditions.append("""c.id IN (
            SELECT ct.comic_id FROM comic_tags ct
            JOIN tags t ON ct.tag_id = t.id WHERE t.name = ?)""")
        params.append(tag_filter)

    comics = db.execute(query, params).fetchall()
    publishers = [r['publisher'] for r in db.execute(
        "SELECT DISTINCT publisher FROM comics ORDER BY publisher"
    ).fetchall()]
    total = db.execute("SELECT COUNT(*) FROM comics").fetchone()[0]
    all_tags = db.execute("""
        SELECT t.name, COUNT(ct.comic_id) as count
        FROM tags t JOIN comic_tags ct ON t.id = ct.tag_id
        GROUP BY t.name ORDER BY count DESC, t.name
    """).fetchall()
    continuing = db.execute("""
        SELECT c.id, c.title, c.series, c.publisher, c.page_count,
               rp.current_page as progress
        FROM reading_progress rp
        JOIN comics c ON rp.comic_id = c.id
        WHERE rp.current_page > 0
          AND (c.page_count = 0 OR rp.current_page < c.page_count - 2)
        ORDER BY rp.last_read DESC LIMIT 5
    """).fetchall()
    db.close()

    return render_template('index.html',
                           comics=comics,
                           publishers=publishers,
                           current_publisher=publisher_filter,
                           search=search,
                           total=total,
                           continuing=continuing,
                           all_tags=all_tags,
                           tag_filter=tag_filter,
                           unrar_missing=not cbr_tool_available())


@app.route('/precache-covers')
def precache_covers():
    """Extract and cache every cover that isn't cached yet."""
    db = get_db()
    comics = db.execute("SELECT id, file_path FROM comics").fetchall()
    db.close()
    done = 0
    for comic in comics:
        already = any(
            os.path.exists(os.path.join(COVER_CACHE_DIR, f"{comic['id']}.{ext}"))
            for ext in ('jpg', 'png')
        )
        if already:
            continue
        img_data, mime = get_page(comic['file_path'], 0)
        if img_data:
            try:
                with open(_cover_cache_path(comic['id'], mime), 'wb') as f:
                    f.write(img_data)
                done += 1
            except Exception as e:
                print(f"Precache failed for {comic['id']}: {e}")
    return redirect(url_for('index'))


@app.route('/scan')
def scan():
    if not os.path.exists(COMICS_DIR):
        return f"Comics directory not found: {COMICS_DIR}", 404

    db = get_db()
    added = 0

    for root, dirs, files in os.walk(COMICS_DIR):
        dirs[:] = sorted(d for d in dirs if not d.startswith('.'))
        for filename in sorted(files):
            if filename.startswith('.'):
                continue
            ext = os.path.splitext(filename)[1].lower()
            if ext not in SUPPORTED_EXTENSIONS:
                continue
            file_path = os.path.join(root, filename)
            meta = extract_metadata(file_path)
            try:
                existing = db.execute(
                    "SELECT id FROM comics WHERE file_path = ?", (file_path,)
                ).fetchone()
                if existing:
                    db.execute(
                        """UPDATE comics SET publisher=?, series=?, issue_number=?
                           WHERE file_path=?""",
                        (meta['publisher'], meta['series'], meta['issue_number'], file_path)
                    )
                else:
                    page_count = get_page_count(file_path)
                    db.execute(
                        """INSERT INTO comics
                           (title, file_path, publisher, series, issue_number, page_count)
                           VALUES (?, ?, ?, ?, ?, ?)""",
                        (meta['title'], file_path, meta['publisher'],
                         meta['series'], meta['issue_number'], page_count)
                    )
                    added += 1
            except Exception as e:
                print(f"Error adding {filename}: {e}")

    db.commit()
    db.close()
    return redirect(url_for('index'))


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
               CASE WHEN f.comic_id IS NOT NULL THEN 1 ELSE 0 END as is_favorite
        FROM comics c
        LEFT JOIN reading_progress rp ON c.id = rp.comic_id
        LEFT JOIN ratings r ON c.id = r.comic_id
        LEFT JOIN favorites f ON c.id = f.comic_id
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
        series    = request.form.get('series', '').strip()
        publisher = request.form.get('publisher', '').strip()
        issue_num = request.form.get('issue_number', '').strip()
        if not title:
            db.close()
            return render_template('edit_comic.html', comic=comic, error='Title is required.')
        db.execute(
            "UPDATE comics SET title=?, series=?, publisher=?, issue_number=? WHERE id=?",
            (title, series or 'General', publisher or 'Unknown', issue_num or None, comic_id)
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
    comic = db.execute("SELECT * FROM comics WHERE id = ?", (comic_id,)).fetchone()
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

    db.close()
    return render_template('reader.html',
                           comic=comic,
                           current_page=current_page,
                           run_context=run_context,
                           prev_comic=prev_comic,
                           next_comic=next_comic,
                           run_id=run_id)


# ── API ──────────────────────────────────────────────────────────────────────

@app.route('/api/progress/<int:comic_id>', methods=['POST'])
def save_progress(comic_id):
    page = request.get_json().get('page', 0)
    db = get_db()
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
    data = request.get_json()
    rating = data.get('rating')
    review = data.get('review', '')
    if not rating or not (1 <= int(rating) <= 5):
        return jsonify({'error': 'Invalid rating'}), 400
    db = get_db()
    db.execute(
        """INSERT INTO ratings (comic_id, rating, review) VALUES (?, ?, ?)
           ON CONFLICT(comic_id) DO UPDATE SET rating = ?, review = ?""",
        (comic_id, rating, review, rating, review)
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
    db.close()
    return render_template('stats.html',
        total_comics=total_comics, read_count=read_count,
        pages_read=pages_read, in_progress=in_progress,
        fav_count=fav_count, runs_count=runs_count,
        by_publisher=by_publisher, top_series=top_series,
        recent_reads=recent_reads)


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
        ORDER BY publisher, series, title
    """, (run_id,)).fetchall()

    db.close()
    return render_template('run_detail.html', run=run, items=items, all_comics=all_comics)


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


@app.route('/runs/<int:run_id>/move/<int:item_id>/<direction>', methods=['POST'])
def move_item(run_id, item_id, direction):
    db = get_db()
    items = db.execute(
        "SELECT * FROM run_items WHERE run_id = ? ORDER BY position", (run_id,)
    ).fetchall()
    for i, item in enumerate(items):
        if item['id'] == item_id:
            if direction == 'up' and i > 0:
                db.execute("UPDATE run_items SET position = ? WHERE id = ?", (items[i-1]['position'], item_id))
                db.execute("UPDATE run_items SET position = ? WHERE id = ?", (item['position'], items[i-1]['id']))
            elif direction == 'down' and i < len(items) - 1:
                db.execute("UPDATE run_items SET position = ? WHERE id = ?", (items[i+1]['position'], item_id))
                db.execute("UPDATE run_items SET position = ? WHERE id = ?", (item['position'], items[i+1]['id']))
            break
    db.commit()
    db.close()
    return redirect(url_for('run_detail', run_id=run_id))


@app.route('/api/rate-run/<int:run_id>', methods=['POST'])
def rate_run(run_id):
    data = request.get_json()
    rating = data.get('rating')
    review = data.get('review', '')
    if not rating or not (1 <= int(rating) <= 5):
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
    note = request.get_json().get('note', '')
    db = get_db()
    db.execute("UPDATE run_items SET notes = ? WHERE id = ?", (note or None, item_id))
    db.commit()
    db.close()
    return jsonify({'ok': True})


@app.route('/api/runs/<int:run_id>/reorder', methods=['POST'])
def reorder_run(run_id):
    order = request.get_json().get('order', [])
    db = get_db()
    for pos, item_id in enumerate(order, 1):
        db.execute("UPDATE run_items SET position = ? WHERE id = ? AND run_id = ?",
                   (pos, item_id, run_id))
    db.commit()
    db.close()
    return jsonify({'ok': True})


@app.route('/api/comic/<int:comic_id>/tags', methods=['POST'])
def add_comic_tag(comic_id):
    name = request.get_json().get('name', '').strip().lower()
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


if __name__ == '__main__':
    init_db()
    migrate_db()
    app.run(debug=True, port=5001)
