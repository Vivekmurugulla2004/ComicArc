import os
import sys
import platform


def get_data_dir():
    """Where the database, covers, and uploads live — never inside the app bundle."""
    system = platform.system()
    if system == 'Darwin':
        base = os.path.expanduser('~/Library/Application Support')
    elif system == 'Windows':
        base = os.environ.get('APPDATA', os.path.expanduser('~'))
    else:
        base = os.path.expanduser('~/.local/share')
    path = os.path.join(base, 'ComicArc')
    os.makedirs(path, exist_ok=True)
    return path


def get_resource_dir():
    """Where static/ and templates/ live — inside the bundle when frozen."""
    if getattr(sys, 'frozen', False):
        return sys._MEIPASS
    return os.path.dirname(os.path.abspath(__file__))
