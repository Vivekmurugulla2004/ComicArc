import os
import re
import time
from flask import Flask, render_template, redirect, url_for, request, jsonify, Response, abort
from werkzeug.utils import secure_filename
from database import get_db
from comic_reader import get_page, get_page_count, cbr_tool_available
from config import get_data_dir, get_resource_dir
from onboarding import is_onboarding_done, get_library_path, save_config
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
    search     = request.args.get('q', '').strip()
    sort       = request.args.get('sort', 'publisher')
    view       = request.args.get('view', '')

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

    tag_filter = request.args.get('tag', '').strip()

    if view == 'reading-list':
        conditions.append("c.id IN (SELECT comic_id FROM reading_list)")
    elif publisher_filter != 'All':
        conditions.append("c.publisher = ?")
        params.append(publisher_filter)
    if search:
        conditions.append("(c.title LIKE ? OR c.series LIKE ?)")
        params.extend([f'%{search}%', f'%{search}%'])
    if tag_filter:
        conditions.append("""c.id IN (
            SELECT ct.comic_id FROM comic_tags ct
            JOIN tags t ON ct.tag_id = t.id WHERE t.name = ?)""")
        params.append(tag_filter)
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
    publishers = [r['publisher'] for r in db.execute(
        "SELECT DISTINCT publisher FROM comics ORDER BY publisher"
    ).fetchall()]
    total = db.execute("SELECT COUNT(*) FROM comics").fetchone()[0]
    reading_list_count = db.execute("SELECT COUNT(*) FROM reading_list").fetchone()[0]
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
    has_cbr = (not cbr_tool_available()) and (
        db.execute("SELECT 1 FROM comics WHERE file_path LIKE '%.cbr' LIMIT 1").fetchone() is not None
    )
    db.close()

    return render_template('index.html',
                           comics=comics,
                           publishers=publishers,
                           current_publisher=publisher_filter,
                           search=search,
                           sort=sort,
                           view=view,
                           total=total,
                           reading_list_count=reading_list_count,
                           continuing=continuing,
                           all_tags=all_tags,
                           tag_filter=tag_filter,
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

    db.close()
    from onboarding import get_reader_mode
    return render_template('reader.html',
                           comic=comic,
                           current_page=current_page,
                           existing_rating=comic['rating'] or 0,
                           run_context=run_context,
                           prev_comic=prev_comic,
                           next_comic=next_comic,
                           run_id=run_id,
                           reader_mode=get_reader_mode())


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
    from onboarding import load_config
    from comic_reader import cbr_tool_available, _find_bin
    import shutil
    cfg = load_config()
    return render_template('settings.html',
                           library_path=cfg.get('library_path', ''),
                           reader_mode=cfg.get('reader_mode', 'page'),
                           cbr_ok=cbr_tool_available(),
                           brew_ok=bool(shutil.which('brew') or _find_bin('brew')),
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
    if updates:
        save_config(updates)
    return jsonify({'ok': True})


@app.route('/api/settings/install-cbr', methods=['POST'])
def install_cbr():
    import threading, subprocess, shutil
    from comic_reader import _find_bin
    if _cbr_install_state['running']:
        return jsonify({'ok': False, 'error': 'Already running'})
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
    db = get_db()
    for comic_id in ids:
        row = db.execute("SELECT file_path FROM comics WHERE id = ?", (comic_id,)).fetchone()
        db.execute("DELETE FROM reading_progress WHERE comic_id = ?", (comic_id,))
        db.execute("DELETE FROM ratings WHERE comic_id = ?", (comic_id,))
        db.execute("DELETE FROM comics WHERE id = ?", (comic_id,))
        if row:
            for ext in ('jpg', 'png'):
                cp = os.path.join(COVER_CACHE_DIR, f'{comic_id}.{ext}')
                if os.path.exists(cp): os.remove(cp)
            if row['file_path'].startswith(UPLOAD_DIR):
                try: os.remove(row['file_path'])
                except OSError: pass
    db.commit()
    db.close()
    return jsonify({'ok': True})


@app.route('/api/bulk/mark-read', methods=['POST'])
def bulk_mark_read():
    ids = (request.get_json(silent=True) or {}).get('ids', [])
    db = get_db()
    for comic_id in ids:
        row = db.execute("SELECT page_count FROM comics WHERE id = ?", (comic_id,)).fetchone()
        if row:
            last = max(row['page_count'] - 1, 0)
            db.execute(
                """INSERT INTO reading_progress (comic_id, current_page, last_read)
                   VALUES (?, ?, CURRENT_TIMESTAMP)
                   ON CONFLICT(comic_id) DO UPDATE SET current_page=?, last_read=CURRENT_TIMESTAMP""",
                (comic_id, last, last)
            )
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


# ── Export ────────────────────────────────────────────────────────────────────

@app.route('/api/export')
def export_library():
    import json as _json
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
        headers={'Content-Disposition': f'attachment; filename={filename}'}
    )
