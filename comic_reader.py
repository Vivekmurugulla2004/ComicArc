import zipfile
import os
import platform
import re
import shutil
import subprocess
import tempfile
import threading
import time
from functools import lru_cache

try:
    import fitz  # PyMuPDF
    PDF_SUPPORT = True
except ImportError:
    PDF_SUPPORT = False

_pdf_cache = {}       # path -> (doc, per_doc_lock, last_access)
_pdf_cache_lock = threading.Lock()   # guards _pdf_cache dict itself
_PDF_CACHE_TTL = 60


def _get_pdf_doc(file_path):
    """Return (doc, per_doc_lock) — caller must acquire the lock before using doc."""
    now = time.monotonic()
    with _pdf_cache_lock:
        entry = _pdf_cache.get(file_path)
        if entry:
            doc, doc_lock, _ = entry
            _pdf_cache[file_path] = (doc, doc_lock, now)
        else:
            doc = fitz.open(file_path)
            doc_lock = threading.Lock()
            _pdf_cache[file_path] = (doc, doc_lock, now)
        expired = [p for p, (_, __, ts) in _pdf_cache.items()
                   if now - ts > _PDF_CACHE_TTL and p != file_path]
        for p in expired:
            try:
                _pdf_cache.pop(p)[0].close()
            except Exception:
                pass
        return doc, doc_lock

_IMAGE_EXTS = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'}


def natural_sort_key(s):
    return [int(c) if c.isdigit() else c.lower() for c in re.split(r'(\d+)', s)]


def get_image_files(file_list):
    return sorted(
        [f for f in file_list
         if os.path.splitext(f)[1].lower() in _IMAGE_EXTS
         and not os.path.basename(f).startswith('.')],
        key=natural_sort_key
    )


def _find_bin(name):
    found = shutil.which(name)
    if found:
        return found
    if platform.system() == 'Windows':
        for prefix in (
            os.path.join(os.environ.get('ProgramFiles', r'C:\Program Files'), name),
            os.path.join(os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)'), name),
            os.path.join(os.environ.get('LOCALAPPDATA', ''), name),
        ):
            if os.path.exists(prefix):
                return prefix
    else:
        for prefix in ('/opt/homebrew/bin', '/usr/local/bin', '/usr/bin'):
            p = os.path.join(prefix, name)
            if os.path.exists(p):
                return p
    return None

def _unar():
    return _find_bin('unar')


def _lsar():
    return _find_bin('lsar')


def _unrar():
    return _find_bin('unrar')


def _7zip():
    if platform.system() == 'Windows':
        for path in [
            r'C:\Program Files\7-Zip\7z.exe',
            r'C:\Program Files (x86)\7-Zip\7z.exe',
        ]:
            if os.path.exists(path):
                return path
    return _find_bin('7z')

def cbr_tool_available():
    return bool(_unar() or _unrar() or _7zip())


@lru_cache(maxsize=32)
def _unar_list(file_path):
    lsar = _lsar()
    if not lsar:
        return []
    result = subprocess.run([lsar, file_path], capture_output=True, text=True, timeout=15)
    images = [
        line.strip() for line in result.stdout.splitlines()
        if os.path.splitext(line.strip())[1].lower() in _IMAGE_EXTS
        and not os.path.basename(line.strip()).startswith('.')
    ]
    return sorted(images, key=natural_sort_key)


def _read_extracted(tmpdir):
    for root, _, files in os.walk(tmpdir):
        for f in sorted(files):
            if os.path.splitext(f)[1].lower() in _IMAGE_EXTS:
                with open(os.path.join(root, f), 'rb') as fp:
                    return fp.read(), _mime(f)
    return None, None


def _unar_page(file_path, page_num):
    images = _unar_list(file_path)
    if page_num >= len(images):
        return None, None
    with tempfile.TemporaryDirectory() as tmpdir:
        subprocess.run(
            [_unar(), '-o', tmpdir, '-force-overwrite', file_path, images[page_num]],
            capture_output=True, timeout=30
        )
        return _read_extracted(tmpdir)


@lru_cache(maxsize=32)
def _7zip_list(file_path):
    z7 = _7zip()
    if not z7:
        return []
    result = subprocess.run(
        [z7, 'l', '-slt', '-ba', file_path],
        capture_output=True, text=True, timeout=15
    )
    images = [
        line[7:].strip() for line in result.stdout.splitlines()
        if line.startswith('Path = ')
        and os.path.splitext(line[7:].strip())[1].lower() in _IMAGE_EXTS
        and not os.path.basename(line[7:].strip()).startswith('.')
    ]
    return sorted(images, key=natural_sort_key)


def _7zip_page(file_path, page_num):
    images = _7zip_list(file_path)
    if page_num >= len(images):
        return None, None
    with tempfile.TemporaryDirectory() as tmpdir:
        subprocess.run(
            [_7zip(), 'e', f'-o{tmpdir}', '-y', file_path, images[page_num]],
            capture_output=True, timeout=30
        )
        return _read_extracted(tmpdir)


def _rarfile_page(file_path, page_num):
    try:
        import rarfile
        with rarfile.RarFile(file_path) as r:
            images = get_image_files(r.namelist())
            if page_num >= len(images):
                return None, None
            return r.read(images[page_num]), _mime(images[page_num])
    except Exception as e:
        print(f"rarfile error: {e}")
        return None, None


def _rarfile_count(file_path):
    try:
        import rarfile
        with rarfile.RarFile(file_path) as r:
            return len(get_image_files(r.namelist()))
    except Exception:
        return 0


def get_page_count(file_path):
    ext = os.path.splitext(file_path)[1].lower()
    try:
        if ext in _IMAGE_EXTS:
            return 1
        elif ext == '.cbz':
            with zipfile.ZipFile(file_path) as z:
                return len(get_image_files(z.namelist()))
        elif ext == '.cbr':
            if _unar():
                return len(_unar_list(file_path))
            elif _unrar():
                return _rarfile_count(file_path)
            elif _7zip():
                return len(_7zip_list(file_path))
        elif ext == '.pdf' and PDF_SUPPORT:
            doc, doc_lock = _get_pdf_doc(file_path)
            with doc_lock:
                return len(doc)
    except Exception as e:
        print(f"Error counting pages in {file_path}: {e}")
    return 0


def get_page(file_path, page_num):
    ext = os.path.splitext(file_path)[1].lower()
    try:
        if ext in _IMAGE_EXTS:
            if page_num != 0:
                return None, None
            with open(file_path, 'rb') as f:
                return f.read(), _mime(file_path)

        elif ext == '.cbz':
            with zipfile.ZipFile(file_path) as z:
                images = get_image_files(z.namelist())
                if page_num >= len(images):
                    return None, None
                return z.read(images[page_num]), _mime(images[page_num])

        elif ext == '.cbr':
            if _unar():
                return _unar_page(file_path, page_num)
            elif _unrar():
                return _rarfile_page(file_path, page_num)
            elif _7zip():
                return _7zip_page(file_path, page_num)

        elif ext == '.pdf' and PDF_SUPPORT:
            doc, doc_lock = _get_pdf_doc(file_path)
            with doc_lock:
                if page_num >= len(doc):
                    return None, None
                pix = doc[page_num].get_pixmap(matrix=fitz.Matrix(1.5, 1.5))
                return pix.tobytes('jpeg'), 'image/jpeg'

    except Exception as e:
        print(f"Error reading page {page_num} from {file_path}: {e}")

    return None, None


def _mime(filename):
    ext = os.path.splitext(filename)[1].lower().lstrip('.')
    return {
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'gif': 'image/gif',
        'webp': 'image/webp',
        'bmp': 'image/bmp',
    }.get(ext, 'image/jpeg')
