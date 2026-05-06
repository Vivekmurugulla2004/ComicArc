import zipfile
import io
import os
import re

try:
    import rarfile
    RAR_SUPPORT = True
except ImportError:
    RAR_SUPPORT = False

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


def get_page_count(file_path):
    ext = os.path.splitext(file_path)[1].lower()
    try:
        if ext == '.cbz':
            with zipfile.ZipFile(file_path) as z:
                return len(get_image_files(z.namelist()))
        elif ext == '.cbr' and RAR_SUPPORT:
            with rarfile.RarFile(file_path) as r:
                return len(get_image_files(r.namelist()))
        elif ext == '.pdf' and PDF_SUPPORT:
            doc = fitz.open(file_path)
            count = len(doc)
            doc.close()
            return count
    except Exception as e:
        print(f"Error counting pages in {file_path}: {e}")
    return 0


def get_page(file_path, page_num):
    """Returns (image_bytes, mime_type) for a given page (0-indexed)."""
    ext = os.path.splitext(file_path)[1].lower()
    try:
        if ext == '.cbz':
            with zipfile.ZipFile(file_path) as z:
                images = get_image_files(z.namelist())
                if page_num >= len(images):
                    return None, None
                img_data = z.read(images[page_num])
                return img_data, _mime(images[page_num])

        elif ext == '.cbr' and RAR_SUPPORT:
            with rarfile.RarFile(file_path) as r:
                images = get_image_files(r.namelist())
                if page_num >= len(images):
                    return None, None
                img_data = r.read(images[page_num])
                return img_data, _mime(images[page_num])

        elif ext == '.pdf' and PDF_SUPPORT:
            doc = fitz.open(file_path)
            if page_num >= len(doc):
                doc.close()
                return None, None
            page = doc[page_num]
            mat = fitz.Matrix(2, 2)
            pix = page.get_pixmap(matrix=mat)
            img_data = pix.tobytes('png')
            doc.close()
            return img_data, 'image/png'

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
