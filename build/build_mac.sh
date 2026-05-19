#!/bin/bash
set -e
cd "$(dirname "$0")/.."
source venv/bin/activate
pip install pyinstaller --quiet
pyinstaller build/ComicArc.spec --clean --noconfirm
echo ""
echo "Done: dist/ComicArc.app"
echo "To create a DMG: hdiutil create -volname ComicArc -srcfolder dist/ComicArc.app -ov -format UDZO dist/ComicArc.dmg"

# Clear dev library so the app starts fresh from onboarding after every build
APP_SUPPORT="$HOME/Library/Application Support/ComicArc"
DB_PATH="$APP_SUPPORT/comics.db"
CFG_PATH="$APP_SUPPORT/config.json"
echo ""
echo "Clearing dev library for fresh onboarding..."
rm -f "$DB_PATH"
if [ -f "$CFG_PATH" ]; then
  python3 -c "
import json, sys
try:
    with open(sys.argv[1]) as f: d = json.load(f)
    d['onboarding_done'] = False
    with open(sys.argv[1], 'w') as f: json.dump(d, f, indent=2)
except Exception: pass
" "$CFG_PATH" 2>/dev/null || rm -f "$CFG_PATH"
fi
echo "Library cleared — app will start from onboarding."
