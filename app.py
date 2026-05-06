import os
import re
from flask import Flask, render_template, redirect, url_for, request, jsonify, Response, abort
from database import get_db, init_db
from comic_reader import get_page, get_page_count

app = Flask(__name__)

COMICS_DIR = os.path.expanduser('~/Downloads/Comics')
SUPPORTED_EXTENSIONS = {'.cbz', '.cbr', '.pdf'}

PLACEHOLDER_SVG = '''<svg xmlns="http://www.w3.org/2000/svg" width="200" height="300" viewBox="0 0 200 300">
  <rect width="200" height="300" fill="#1e1e2e"/>
  <rect x="20" y="20" width="160" height="260" fill="none" stroke="#333" stroke-width="2"/>
  <text x="100" y="155" text-anchor="middle" fill="#444" font-family="sans-serif" font-size="13">No Cover</text>
</svg>'''


def extract_metadata(file_path):
    rel = os.path.relpath(file_path, COMICS_DIR)
    parts = rel.split(os.sep)
    publisher = parts[0] if len(parts) > 1 else 'Unknown'
    series = parts[1] if len(parts) > 2 else 'General'
    filename = parts[-1]
    title = os.path.splitext(filename)[0]
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
               COALESCE(r.rating, 0) as rating
        FROM comics c
        LEFT JOIN reading_progress rp ON c.id = rp.comic_id
        LEFT JOIN ratings r ON c.id = r.comic_id
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

    comics = db.execute(query, params).fetchall()
    publishers = [r['publisher'] for r in db.execute(
        "SELECT DISTINCT publisher FROM comics ORDER BY publisher"
    ).fetchall()]
    total = db.execute("SELECT COUNT(*) FROM comics").fetchone()[0]
    db.close()

    return render_template('index.html',
                           comics=comics,
                           publishers=publishers,
                           current_publisher=publisher_filter,
                           search=search,
                           total=total)


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
            page_count = get_page_count(file_path)
            try:
                db.execute(
                    """INSERT OR IGNORE INTO comics
                       (title, file_path, publisher, series, issue_number, page_count)
                       VALUES (?, ?, ?, ?, ?, ?)""",
                    (meta['title'], file_path, meta['publisher'],
                     meta['series'], meta['issue_number'], page_count)
                )
                if db.execute("SELECT changes()").fetchone()[0]:
                    added += 1
            except Exception as e:
                print(f"Error adding {filename}: {e}")

    db.commit()
    db.close()
    return redirect(url_for('index'))


# ── Images ───────────────────────────────────────────────────────────────────

@app.route('/cover/<int:comic_id>')
def serve_cover(comic_id):
    db = get_db()
    row = db.execute("SELECT file_path FROM comics WHERE id = ?", (comic_id,)).fetchone()
    db.close()
    if not row:
        return Response(PLACEHOLDER_SVG, mimetype='image/svg+xml')
    img_data, mime = get_page(row['file_path'], 0)
    if not img_data:
        return Response(PLACEHOLDER_SVG, mimetype='image/svg+xml')
    resp = Response(img_data, mimetype=mime)
    resp.headers['Cache-Control'] = 'public, max-age=3600'
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

@app.route('/runs')
def runs():
    db = get_db()
    runs_list = db.execute("""
        SELECT r.*, COUNT(ri.id) as comic_count
        FROM runs r
        LEFT JOIN run_items ri ON r.id = ri.run_id
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
        db = get_db()
        cur = db.execute("INSERT INTO runs (title, description) VALUES (?, ?)", (title, description))
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
               COALESCE(rp.current_page, 0) as progress
        FROM run_items ri
        JOIN comics c ON ri.comic_id = c.id
        LEFT JOIN reading_progress rp ON c.id = rp.comic_id
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


@app.route('/runs/<int:run_id>/delete', methods=['POST'])
def delete_run(run_id):
    db = get_db()
    db.execute("DELETE FROM runs WHERE id = ?", (run_id,))
    db.commit()
    db.close()
    return redirect(url_for('runs'))


if __name__ == '__main__':
    init_db()
    app.run(debug=True, port=5001)
