import json
import os
from config import get_data_dir

_CONFIG_PATH = os.path.join(get_data_dir(), 'config.json')
_config_cache = None
_config_mtime = None


def load_config():
    global _config_cache, _config_mtime
    try:
        mtime = os.path.getmtime(_CONFIG_PATH)
    except OSError:
        return {}
    if _config_cache is not None and mtime == _config_mtime:
        return _config_cache
    try:
        with open(_CONFIG_PATH) as f:
            _config_cache = json.load(f)
        _config_mtime = mtime
        return _config_cache
    except Exception:
        return {}


def save_config(updates):
    global _config_cache, _config_mtime
    cfg = load_config()
    cfg.update(updates)
    with open(_CONFIG_PATH, 'w') as f:
        json.dump(cfg, f, indent=2)
    _config_cache = cfg
    try:
        _config_mtime = os.path.getmtime(_CONFIG_PATH)
    except OSError:
        _config_mtime = None


def is_onboarding_done():
    return bool(load_config().get('onboarding_done'))


def get_library_path():
    return load_config().get('library_path', '')


def get_reader_mode():
    return load_config().get('reader_mode', 'page')


def get_autoplay_interval():
    return int(load_config().get('autoplay_interval', 10))
