import os
import re
import threading
from database import get_db
from comic_reader import get_page_count

SUPPORTED = {'.cbz', '.cbr', '.pdf', '.jpg', '.jpeg', '.png'}

_state = {'running': False, 'total': 0, 'done': 0, 'added': 0}
_lock = threading.Lock()


def get_status():
    with _lock:
        return dict(_state)


def _file_sig(path):
    try:
        return f"{os.path.basename(path)}:{os.path.getsize(path)}"
    except OSError:
        return None


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
        character, series = None, mid[0]
    else:
        character, series = mid[-2], mid[-1]
    m = re.search(r'(?:v|vol|volume|#|issue)[\s.]?(\d+)', title, re.IGNORECASE)
    return {'publisher': publisher, 'character': character, 'series': series,
            'title': title, 'issue_number': m.group(1) if m else None}


def _run(library_path):
    with _lock:
        _state.update({'running': True, 'total': 0, 'done': 0, 'added': 0})

    all_files = []
    for root, dirs, files in os.walk(library_path):
        dirs[:] = sorted(d for d in dirs if not d.startswith('.'))
        for f in sorted(files):
            if not f.startswith('.') and os.path.splitext(f)[1].lower() in SUPPORTED:
                all_files.append(os.path.join(root, f))

    with _lock:
        _state['total'] = len(all_files)

    db = get_db()
    known_sigs = set()
    for row in db.execute("SELECT file_path FROM comics").fetchall():
        s = _file_sig(row['file_path'])
        if s:
            known_sigs.add(s)

    added = 0
    for i, fp in enumerate(all_files):
        try:
            sig = _file_sig(fp)
            row = db.execute("SELECT id FROM comics WHERE file_path = ?", (fp,)).fetchone()
            if row:
                pass  # already in library — don't overwrite user-edited metadata
            elif sig and sig in known_sigs:
                pass  # same name+size already in library under a different path
            else:
                m = _meta(fp, library_path)
                pc = get_page_count(fp)
                db.execute(
                    """INSERT INTO comics
                       (title, file_path, publisher, character, series, issue_number, page_count)
                       VALUES (?, ?, ?, ?, ?, ?, ?)""",
                    (m['title'], fp, m['publisher'], m['character'], m['series'], m['issue_number'], pc)
                )
                added += 1
                if sig:
                    known_sigs.add(sig)
        except Exception as e:
            print(f"[scanner] skip {fp}: {e}")

        with _lock:
            _state['done'] = i + 1
            _state['added'] = added

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
