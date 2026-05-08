import json
import os
from config import get_data_dir

_CONFIG_PATH = os.path.join(get_data_dir(), 'config.json')


def load_config():
    if not os.path.exists(_CONFIG_PATH):
        return {}
    try:
        with open(_CONFIG_PATH) as f:
            return json.load(f)
    except Exception:
        return {}


def save_config(updates):
    cfg = load_config()
    cfg.update(updates)
    with open(_CONFIG_PATH, 'w') as f:
        json.dump(cfg, f, indent=2)


def is_onboarding_done():
    return bool(load_config().get('onboarding_done'))


def get_library_path():
    return load_config().get('library_path', '')


def get_reader_mode():
    return load_config().get('reader_mode', 'page')
