import os
import re
import threading
import zipfile
import xml.etree.ElementTree as ET
from database import get_db
from comic_reader import get_page_count

SUPPORTED = {'.cbz', '.cbr', '.pdf', '.jpg', '.jpeg', '.png'}

_state = {'running': False, 'total': 0, 'done': 0, 'added': 0, 'cancelled': False, 'duplicates': []}
_lock = threading.Lock()


def get_duplicates():
    """Return list of {title, issue_number, paths} groups with >1 entry."""
    with _lock:
        return list(_state['duplicates'])


def get_status():
    with _lock:
        return dict(_state)


def _file_sig(path):
    """Unique-enough fingerprint: full path + size. Full path avoids false
    deduplication of two different files that happen to share a filename and
    byte count — the old basename-only approach was collision-prone."""
    try:
        return f"{path}:{os.path.getsize(path)}"
    except OSError:
        return None


def _read_comicinfo(file_path):
    """Extract ComicInfo.xml metadata from a CBZ/ZIP file. Returns dict or {}."""
    ext = os.path.splitext(file_path)[1].lower()
    if ext not in ('.cbz', '.zip'):
        return {}
    try:
        with zipfile.ZipFile(file_path, 'r') as zf:
            names = [n for n in zf.namelist() if os.path.basename(n).lower() == 'comicinfo.xml']
            if not names:
                return {}
            with zf.open(names[0]) as f:
                root = ET.parse(f).getroot()
        def get(tag):
            el = root.find(tag)
            return el.text.strip() if el is not None and el.text else None
        result = {}
        if get('Series'):      result['series']      = get('Series')
        if get('Publisher'):   result['publisher']   = get('Publisher')
        if get('Writer'):      result['writer']      = get('Writer')
        if get('Penciller'):   result['penciller']   = get('Penciller')
        if get('Year'):
            try: result['year'] = int(get('Year'))
            except ValueError: pass
        if get('StoryArc'):    result['story_arc']   = get('StoryArc')
        if get('LanguageISO'): result['language_iso'] = get('LanguageISO')
        num = get('Number')
        if num:
            m = re.search(r'(\d+)', num)
            if m: result['issue_number'] = m.group(1)
        title = get('Title')
        if title: result['title_override'] = title
        return result
    except Exception:
        return {}


def _normalize_series(name):
    """Strip trailing year suffixes and extra whitespace so variants of the same
    series name group together.  E.g. 'Ultimate Spider-Man (2000)' → 'Ultimate Spider-Man'."""
    if not name:
        return name
    name = name.strip()
    # Remove trailing parenthesised year: "(2000)", "(2000-2009)", "(Vol. 1)"
    name = re.sub(r'\s*\([^)]*\)\s*$', '', name).strip()
    # Remove trailing volume marker: "Vol. 1", "Vol 2"
    name = re.sub(r'\s+[Vv]ol\.?\s*\d+\s*$', '', name).strip()
    return name


def _meta(file_path, base):
    rel = os.path.relpath(file_path, base)
    parts = rel.split(os.sep)
    publisher = parts[0] if len(parts) > 1 else 'Unknown'
    filename = parts[-1]
    title = os.path.splitext(filename)[0]
    mid = parts[1:-1]
    if not mid:
        character, series = None, 'General'
    elif len(mid) == 1:
        character, series = None, _normalize_series(mid[0])
    else:
        character, series = mid[-2], _normalize_series(mid[-1])
    m = re.search(r'(?:v|vol|volume|#|issue)[\s.]?(\d+)', title, re.IGNORECASE)
    return {'publisher': publisher, 'character': character, 'series': series,
            'title': title, 'issue_number': m.group(1) if m else None,
            'writer': None, 'penciller': None, 'year': None,
            'story_arc': None, 'language_iso': None}


def _run(library_path):
    with _lock:
        _state.update({'running': True, 'total': 0, 'done': 0, 'added': 0, 'cancelled': False, 'duplicates': []})

    all_files = []
    for root, dirs, files in os.walk(library_path):
        dirs[:] = sorted(d for d in dirs if not d.startswith('.'))
        for f in sorted(files):
            if not f.startswith('.') and os.path.splitext(f)[1].lower() in SUPPORTED:
                all_files.append(os.path.join(root, f))

    with _lock:
        _state['total'] = len(all_files)

    db = get_db()
    # Load all known paths and signatures in one query — avoids N per-file lookups.
    known_paths = set()
    known_sigs = set()
    for row in db.execute("SELECT file_path FROM comics").fetchall():
        known_paths.add(row['file_path'])
        s = _file_sig(row['file_path'])
        if s:
            known_sigs.add(s)

    added = 0
    for i, fp in enumerate(all_files):
        with _lock:
            if _state.get('cancelled'):
                break
        try:
            sig = _file_sig(fp)
            if fp in known_paths:
                pass  # already in library — don't overwrite user-edited metadata
            elif sig and sig in known_sigs:
                pass  # same name+size already in library under a different path
            else:
                m = _meta(fp, library_path)
                ci = _read_comicinfo(fp)
                # ComicInfo.xml overrides path-derived metadata where present.
                # Normalize series names from both sources to avoid spurious splits.
                title      = ci.get('title_override') or m['title']
                publisher  = ci.get('publisher')  or m['publisher']
                series     = _normalize_series(ci.get('series') or m['series'])
                issue_num  = ci.get('issue_number') or m['issue_number']
                pc = get_page_count(fp)
                db.execute(
                    """INSERT INTO comics
                       (title, file_path, publisher, character, series, issue_number,
                        page_count, writer, penciller, year, story_arc, language_iso)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                    (title, fp, publisher, m['character'], series, issue_num, pc,
                     ci.get('writer'), ci.get('penciller'), ci.get('year'),
                     ci.get('story_arc'), ci.get('language_iso'))
                )
                added += 1
                known_paths.add(fp)
                if sig:
                    known_sigs.add(sig)
        except Exception as e:
            print(f"[scanner] skip {fp}: {e}")

        # Batch progress updates every 25 files to reduce lock contention.
        if i % 25 == 0 or i == len(all_files) - 1:
            with _lock:
                _state['done'] = i + 1
                _state['added'] = added

    # Detect duplicates: same (title, issue_number) combination in the active library
    dup_rows = db.execute("""
        SELECT title, issue_number, COUNT(*) as cnt
        FROM comics
        WHERE deleted_at IS NULL AND issue_number IS NOT NULL AND issue_number != ''
        GROUP BY LOWER(title), issue_number
        HAVING cnt > 1
    """).fetchall()
    dups = []
    for row in dup_rows:
        paths = [r['file_path'] for r in db.execute(
            "SELECT file_path FROM comics WHERE LOWER(title)=LOWER(?) AND issue_number=? AND deleted_at IS NULL",
            (row['title'], row['issue_number'])
        ).fetchall()]
        dups.append({'title': row['title'], 'issue_number': row['issue_number'], 'paths': paths})
    with _lock:
        _state['duplicates'] = dups

    # Prune stale entries: comics under library_path whose file no longer exists
    stale = [
        row['id'] for row in db.execute("SELECT id, file_path FROM comics").fetchall()
        if row['file_path'].startswith(library_path) and not os.path.exists(row['file_path'])
    ]
    if stale:
        ph = ','.join('?' * len(stale))
        for tbl, col in [('reading_progress', 'comic_id'), ('ratings', 'comic_id'),
                         ('favorites', 'comic_id'), ('comic_tags', 'comic_id'),
                         ('run_items', 'comic_id'), ('reading_list', 'comic_id')]:
            db.execute(f"DELETE FROM {tbl} WHERE {col} IN ({ph})", stale)
        db.execute(f"DELETE FROM comics WHERE id IN ({ph})", stale)

    db.commit()
    db.close()
    with _lock:
        _state['running'] = False


def scan_library(library_path):
    """Start a background scan. Returns False if already running or path invalid."""
    with _lock:
        if _state['running']:
            return False
    if not os.path.isdir(library_path):
        return False
    threading.Thread(target=_run, args=(library_path,), daemon=True).start()
    return True


def cancel_scan():
    """Signal the running scan to stop after its current file."""
    with _lock:
        if _state['running']:
            _state['cancelled'] = True
