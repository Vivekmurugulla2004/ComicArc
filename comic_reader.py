import zipfile
import os
import re
import shutil
import subprocess
import tempfile

try:
    import fitz  # PyMuPDF
    PDF_SUPPORT = True
except ImportError:
    PDF_SUPPORT = False


def natural_sort_key(s):
    return [int(c) if c.isdigit() else c.lower() for c in re.split(r'(\d+)', s)]


def get_image_files(file_list):
    extensions = ('.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp')
    images = [
        f for f in file_list
        if f.lower().endswith(extensions) and not os.path.basename(f).startswith('.')
    ]
    return sorted(images, key=natural_sort_key)


def _find_bin(name):
    found = shutil.which(name)
    if found:
        return found
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
    import platform
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


# ── CBR via unar/lsar ────────────────────────────────────────────────────────

def _unar_list(file_path):
    """Return sorted list of image paths inside a CBR using lsar."""
    lsar = _lsar()
    if not lsar:
        return []
    result = subprocess.run(
        [lsar, file_path],
        capture_output=True, text=True, timeout=15
    )
    images = []
    for line in result.stdout.splitlines():
        line = line.strip()
        if any(line.lower().endswith(ext) for ext in ('.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp')):
            if not os.path.basename(line).startswith('.'):
                images.append(line)
    return sorted(images, key=natural_sort_key)


def _unar_page(file_path, page_num):
    """Extract a single page from a CBR using unar."""
    images = _unar_list(file_path)
    if page_num >= len(images):
        return None, None
    target = images[page_num]
    with tempfile.TemporaryDirectory() as tmpdir:
        subprocess.run(
            [_unar(), '-o', tmpdir, '-force-overwrite', file_path, target],
            capture_output=True, timeout=30
        )
        for root, _, files in os.walk(tmpdir):
            for f in sorted(files):
                if any(f.lower().endswith(ext) for ext in ('.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp')):
                    with open(os.path.join(root, f), 'rb') as fp:
                        return fp.read(), _mime(f)
    return None, None


# ── CBR via 7-Zip ────────────────────────────────────────────────────────────

def _7zip_list(file_path):
    """Return sorted list of image paths inside a CBR using 7z."""
    z7 = _7zip()
    if not z7:
        return []
    result = subprocess.run(
        [z7, 'l', '-slt', '-ba', file_path],
        capture_output=True, text=True, timeout=15
    )
    images = []
    for line in result.stdout.splitlines():
        if line.startswith('Path = '):
            name = line[7:].strip()
            if any(name.lower().endswith(ext) for ext in ('.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp')):
                if not os.path.basename(name).startswith('.'):
                    images.append(name)
    return sorted(images, key=natural_sort_key)


def _7zip_page(file_path, page_num):
    """Extract a single page from a CBR using 7z."""
    images = _7zip_list(file_path)
    if page_num >= len(images):
        return None, None
    target = images[page_num]
    with tempfile.TemporaryDirectory() as tmpdir:
        subprocess.run(
            [_7zip(), 'e', f'-o{tmpdir}', '-y', file_path, target],
            capture_output=True, timeout=30
        )
        for root, _, files in os.walk(tmpdir):
            for f in sorted(files):
                if any(f.lower().endswith(ext) for ext in ('.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp')):
                    with open(os.path.join(root, f), 'rb') as fp:
                        return fp.read(), _mime(f)
    return None, None


# ── CBR via rarfile + unrar ───────────────────────────────────────────────────

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


# ── Public API ────────────────────────────────────────────────────────────────

_IMAGE_EXTS = {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'}

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
            doc = fitz.open(file_path)
            try:
                return len(doc)
            finally:
                doc.close()
    except Exception as e:
        print(f"Error counting pages in {file_path}: {e}")
    return 0


def get_page(file_path, page_num):
    """Returns (image_bytes, mime_type) for a given page (0-indexed)."""
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
            doc = fitz.open(file_path)
            try:
                if page_num >= len(doc):
                    return None, None
                pix = doc[page_num].get_pixmap(matrix=fitz.Matrix(2, 2))
                return pix.tobytes('png'), 'image/png'
            finally:
                doc.close()

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
